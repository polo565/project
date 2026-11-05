package com.polo.adblock

import android.content.Context
import java.util.concurrent.atomic.AtomicLong

/** État partagé entre le service VPN et l'interface. */
object AdBlockState {
    @Volatile
    var running = false

    val blocked = AtomicLong(0)
    val total = AtomicLong(0)

    private val recent = ArrayDeque<String>()

    fun addRecent(domain: String) = synchronized(recent) {
        if (recent.firstOrNull() == domain) return
        recent.addFirst(domain)
        while (recent.size > 50) recent.removeLast()
    }

    fun recentList(): List<String> = synchronized(recent) { recent.toList() }
}

/** Applications dont les publicités sont autorisées (elles ne passent pas par le VPN). */
object AllowedApps {
    private const val KEY = "allowed"

    private fun prefs(context: Context) =
        context.getSharedPreferences("adblock", Context.MODE_PRIVATE)

    fun get(context: Context): Set<String> =
        prefs(context).getStringSet(KEY, emptySet())!!.toSet()

    fun set(context: Context, packages: Collection<String>) {
        prefs(context).edit().putStringSet(KEY, packages.toSet()).apply()
    }
}
