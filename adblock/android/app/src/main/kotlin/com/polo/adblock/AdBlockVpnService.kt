package com.polo.adblock

import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * VPN local qui ne capture que les requêtes DNS : les domaines publicitaires
 * reçoivent une réponse « n'existe pas », les autres sont transmis au vrai DNS.
 * Les applications autorisées sont exclues du VPN et gardent donc leurs pubs.
 */
class AdBlockVpnService : VpnService() {
    companion object {
        const val ACTION_STOP = "com.polo.adblock.STOP"
        private const val VPN_ADDRESS = "10.111.222.2"
        private const val VPN_DNS = "10.111.222.1"
        private val UPSTREAM_DNS = listOf("1.1.1.1", "8.8.8.8")
    }

    private var tun: ParcelFileDescriptor? = null
    private var worker: Thread? = null
    private var pool: ExecutorService? = null

    @Volatile
    private var active = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopVpn()
            stopSelf()
            return START_NOT_STICKY
        }
        startVpn()
        return START_STICKY
    }

    override fun onRevoke() {
        stopVpn()
        stopSelf()
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    private fun startVpn() {
        stopVpn()
        val builder = Builder()
            .setSession("AdBlock")
            .addAddress(VPN_ADDRESS, 32)
            .addDnsServer(VPN_DNS)
            .addRoute(VPN_DNS, 32)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)
        for (pkg in AllowedApps.get(this) + packageName) {
            try {
                builder.addDisallowedApplication(pkg)
            } catch (_: PackageManager.NameNotFoundException) {
                // Application désinstallée entre-temps.
            }
        }
        val fd = builder.establish() ?: return // autorisation VPN retirée
        tun = fd
        pool = Executors.newFixedThreadPool(8)
        active = true
        AdBlockState.running = true
        worker = Thread({ loop(fd) }, "adblock-vpn").also { it.start() }
    }

    private fun stopVpn() {
        active = false
        AdBlockState.running = false
        worker?.join(2000)
        worker = null
        pool?.shutdownNow()
        pool = null
        try {
            tun?.close()
        } catch (_: IOException) {
        }
        tun = null
    }

    private fun loop(fd: ParcelFileDescriptor) {
        Blocklist.ensureLoaded(this)
        val input = FileInputStream(fd.fileDescriptor)
        val output = FileOutputStream(fd.fileDescriptor)
        val buffer = ByteArray(32767)
        val pollFd = StructPollfd().apply {
            this.fd = fd.fileDescriptor
            events = OsConstants.POLLIN.toShort()
        }
        while (active) {
            try {
                if (Os.poll(arrayOf(pollFd), 1000) <= 0) continue
                val n = input.read(buffer)
                if (n > 0) handlePacket(buffer.copyOf(n), output)
            } catch (_: Exception) {
                if (!active) break
            }
        }
    }

    private fun handlePacket(packet: ByteArray, output: FileOutputStream) {
        if (packet.size < 28) return
        if ((packet[0].toInt() shr 4) != 4) return // IPv4 uniquement
        val ihl = (packet[0].toInt() and 0x0F) * 4
        if (packet[9].toInt() != 17) return // UDP
        if (packet.size < ihl + 8 + 12 || u16(packet, ihl + 2) != 53) return
        val dns = packet.copyOfRange(ihl + 8, packet.size)
        val (name, questionEnd) = parseQuestion(dns) ?: return

        AdBlockState.total.incrementAndGet()
        if (Blocklist.isBlocked(name)) {
            AdBlockState.blocked.incrementAndGet()
            AdBlockState.addRecent(name)
            writeResponse(output, packet, ihl, blockedResponse(dns, questionEnd))
        } else {
            pool?.execute { forward(output, packet, ihl, dns) }
        }
    }

    private fun forward(output: FileOutputStream, request: ByteArray, ihl: Int, dns: ByteArray) {
        for (server in UPSTREAM_DNS) {
            try {
                DatagramSocket().use { socket ->
                    protect(socket) // la requête sort directement, sans repasser par le VPN
                    socket.soTimeout = 5000
                    socket.send(DatagramPacket(dns, dns.size, InetAddress.getByName(server), 53))
                    val reply = DatagramPacket(ByteArray(4096), 4096)
                    socket.receive(reply)
                    writeResponse(output, request, ihl, reply.data.copyOf(reply.length))
                }
                return
            } catch (_: IOException) {
                // essaie le serveur suivant
            }
        }
    }

    /** Renvoie (nom demandé, fin de la section question) ou null si la requête est inhabituelle. */
    private fun parseQuestion(dns: ByteArray): Pair<String, Int>? {
        if (u16(dns, 4) != 1) return null
        val name = StringBuilder()
        var pos = 12
        while (true) {
            if (pos >= dns.size) return null
            val len = dns[pos].toInt() and 0xFF
            if (len == 0) {
                pos++
                break
            }
            if (len and 0xC0 != 0 || pos + 1 + len > dns.size) return null
            if (name.isNotEmpty()) name.append('.')
            name.append(String(dns, pos + 1, len, Charsets.US_ASCII))
            pos += 1 + len
        }
        val end = pos + 4
        return if (end <= dns.size) name.toString() to end else null
    }

    /** Réponse NXDOMAIN (« ce domaine n'existe pas »). */
    private fun blockedResponse(dns: ByteArray, questionEnd: Int): ByteArray {
        val r = dns.copyOf(questionEnd)
        r[2] = (0x80 or (dns[2].toInt() and 0x79)).toByte() // QR=1, même opcode et RD
        r[3] = 0x83.toByte() // RA=1, RCODE=3
        for (i in 6 until 12) r[i] = 0 // aucune réponse ni enregistrement additionnel
        return r
    }

    /** Emballe la réponse DNS dans un paquet IPv4/UDP renvoyé à l'application. */
    private fun writeResponse(output: FileOutputStream, request: ByteArray, ihl: Int, payload: ByteArray) {
        val length = 28 + payload.size
        val p = ByteArray(length)
        p[0] = 0x45
        put16(p, 2, length)
        put16(p, 6, 0x4000) // ne pas fragmenter
        p[8] = 64
        p[9] = 17
        System.arraycopy(request, 16, p, 12, 4) // source = ancienne destination
        System.arraycopy(request, 12, p, 16, 4) // destination = ancienne source
        put16(p, 10, checksum(p, 20))
        put16(p, 20, u16(request, ihl + 2))
        put16(p, 22, u16(request, ihl))
        put16(p, 24, 8 + payload.size)
        System.arraycopy(payload, 0, p, 28, payload.size)
        try {
            synchronized(output) { output.write(p) }
        } catch (_: IOException) {
            // VPN arrêté entre-temps
        }
    }

    private fun u16(b: ByteArray, i: Int) = ((b[i].toInt() and 0xFF) shl 8) or (b[i + 1].toInt() and 0xFF)

    private fun put16(b: ByteArray, i: Int, v: Int) {
        b[i] = (v shr 8).toByte()
        b[i + 1] = v.toByte()
    }

    private fun checksum(b: ByteArray, len: Int): Int {
        var sum = 0
        for (i in 0 until len step 2) sum += u16(b, i)
        while (sum shr 16 != 0) sum = (sum and 0xFFFF) + (sum shr 16)
        return sum.inv() and 0xFFFF
    }
}
