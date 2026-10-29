package com.motoristapro.app

data class ScreenOffer(val fare: Double, val distance: Double, val minutes: Int, val rating: Double?, val route: RideRoute = RideRoute())

object ScreenOfferParser {
    private val km = Regex("(?<![0-9.,])([0-9]+(?:[.,][0-9]{1,3})?)\\s*km\\b", RegexOption.IGNORE_CASE)
    private val min = Regex("(?<![0-9])([0-9]+)\\s*(?:min|minutos?|m)\\b", RegexOption.IGNORE_CASE)
    private val hourMinute = Regex("([0-9]+)\\s*h(?:ora)?s?\\s*([0-9]+)\\s*m", RegexOption.IGNORE_CASE)

    fun platformForPackage(name: String?): String? = when (name?.lowercase()) {
        "com.ubercab.driver" -> "Uber"
        "com.taxis99", "com.taxis99.driver", "com.didiglobal.driver" -> "99"
        "sinet.startup.inDriver".lowercase() -> "inDrive"
        else -> null
    }

    fun detectPlatform(text: String): String? {
        val normalized = RideReceiptParser.normalized(text)
        val matches = listOfNotNull(
            "99".takeIf { listOf("taxa99", "99pop", "99 pop", "99moto", "99 moto", "central 99", "motorista 99").any(normalized::contains) },
            "Uber".takeIf { listOf("uber pro", "uberx", "uber moto", "uber flash", "uber comfort").any(normalized::contains) },
            "inDrive".takeIf { normalized.contains("indrive") }
        )
        return matches.singleOrNull()
    }

    fun parse(text: String): ScreenOffer? {
        val rows = RideReceiptParser.lines(text).filterNot { row ->
            val n = RideReceiptParser.normalized(row)
            listOf("acima da meta", "abaixo da meta", "faixa intermedi", "taxa99", "taxa 99", "bonus", "saldo", "meta semanal", "/km", "/h", "motorista pro ativo", "alerta de area", "sem dados de risco").any(n::contains)
        }
        val offerText = rows.joinToString("\n")
        val normalized = RideReceiptParser.normalized(offerText)
        if (RideReceiptParser.parse(offerText) != null) return null
        val hasOfferAction = listOf("aceitar", "selecionar", "aceite", "recusar", "oferta", "solicitacao", "nova corrida", "proxima corrida", "adicionar a fila", "chamada", "ver corrida", "ver oferta").any(normalized::contains)
        if (!hasOfferAction) return null
        if (Regex("\\baceitar\\b").findAll(normalized).count() > 1) return null
        val fares = RideReceiptParser.money.findAll(offerText).mapNotNull { RideReceiptParser.number(it.groupValues[1]) }.distinct().toList()
        if (fares.size != 1 || fares.single() <= 0) return null
        // Do not distinct(): pickup and trip may both be 1.8 km / 6 min.
        val distances = km.findAll(offerText).mapNotNull { RideReceiptParser.number(it.groupValues[1]) }.toList()
        if (distances.size !in 1..2 || distances.any { it <= 0 || it > 1000 }) return null
        val hours = hourMinute.findAll(offerText).toList()
        val durationValues = min.findAll(offerText).filter { m -> hours.none { h -> m.range.first in h.range } }
            .mapNotNull { it.groupValues[1].toIntOrNull() }.toList() + hours.map { it.groupValues[1].toInt() * 60 + it.groupValues[2].toInt() }
        if (durationValues.size !in 1..2 || durationValues.any { it <= 0 || it > 1440 }) return null
        val labeled = RideReceiptParser.route(offerText)
        // 99 uses two time/distance rows followed by the corresponding address.
        val markers = rows.indices.filter { km.containsMatchIn(rows[it]) && min.containsMatchIn(rows[it]) }
        val blocks = if (markers.size == 2) markers.mapIndexed { part, start ->
            rows.subList(start + 1, markers.getOrNull(part + 1) ?: rows.size)
                .takeWhile { !Regex("^(aceitar|recusar|selecionar|ver oferta)\\b").containsMatchIn(RideReceiptParser.normalized(it)) }
                .joinToString(", ") { it.trimEnd(',', ' ') }.takeIf(RideReceiptParser::isAddress)
        } else emptyList()
        val route = RideRoute(labeled.pickup ?: blocks.getOrNull(0), labeled.destination ?: blocks.getOrNull(1))
        val rating = Regex("(?:★|⭐|nota)\\s*[: -]?\\s*([3-5][.,][0-9]{1,2})", RegexOption.IGNORE_CASE)
            .find(offerText)?.groupValues?.get(1)?.let(RideReceiptParser::number)
        return ScreenOffer(fares.single(), distances.sum(), durationValues.sum(), rating, route)
    }

    fun isActiveRide(text: String): Boolean {
        val n = RideReceiptParser.normalized(text)
        return listOf("corrida em andamento", "viagem em andamento", "a caminho do passageiro", "cheguei ao local", "cheguei no local", "passageiro embarcou", "deslize para iniciar", "iniciar viagem", "iniciar corrida", "a caminho do destino", "chegar ao destino", "finalizar viagem", "finalizar corrida", "encerrar viagem", "encerrar corrida").any(n::contains)
    }
}
