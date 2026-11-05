package com.polo.adblock

import android.content.Context
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/** Liste des domaines publicitaires bloqués. */
object Blocklist {
    /** Liste « hosts » publique (publicités + traqueurs), mise à jour régulièrement. */
    private const val SOURCE_URL =
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"

    @Volatile
    private var domains: Set<String> = emptySet()

    val size: Int get() = domains.size

    private fun file(context: Context) = File(context.filesDir, "hosts.txt")

    fun lastUpdate(context: Context): Long = file(context).let { if (it.exists()) it.lastModified() else 0L }

    @Synchronized
    fun ensureLoaded(context: Context) {
        if (domains.isNotEmpty()) return
        val f = file(context)
        val text = if (f.exists()) {
            f.readText()
        } else {
            context.assets.open("default_hosts.txt").bufferedReader().use { it.readText() }
        }
        domains = parse(text)
    }

    /** Télécharge la liste complète et renvoie le nombre de domaines. */
    fun download(context: Context): Int {
        val conn = URL(SOURCE_URL).openConnection() as HttpURLConnection
        conn.connectTimeout = 15000
        conn.readTimeout = 30000
        val text = try {
            conn.inputStream.bufferedReader().use { it.readText() }
        } finally {
            conn.disconnect()
        }
        val parsed = parse(text)
        if (parsed.size < 1000) throw IllegalStateException("Liste invalide (${parsed.size} domaines)")
        file(context).writeText(text)
        domains = parsed
        return parsed.size
    }

    /** Vrai si le domaine ou l'un de ses domaines parents est dans la liste. */
    fun isBlocked(name: String): Boolean {
        val set = domains
        var d = name.lowercase().trimEnd('.')
        while (true) {
            if (d in set) return true
            val dot = d.indexOf('.')
            if (dot < 0) return false
            d = d.substring(dot + 1)
        }
    }

    private val ignored = setOf("localhost", "localhost.localdomain", "local", "broadcasthost", "0.0.0.0")

    private fun parse(text: String): Set<String> {
        val result = HashSet<String>()
        for (raw in text.lineSequence()) {
            val line = raw.substringBefore('#').trim()
            if (line.isEmpty()) continue
            val parts = line.split(Regex("\\s+"))
            val domain = when {
                parts.size >= 2 && (parts[0] == "0.0.0.0" || parts[0] == "127.0.0.1") -> parts[1]
                parts.size == 1 -> parts[0]
                else -> continue
            }.lowercase()
            if (domain !in ignored && domain.contains('.')) result.add(domain)
        }
        return result
    }
}
