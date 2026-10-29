package com.motoristapro.app

import java.text.Normalizer
import java.util.Locale

data class RideRoute(val pickup: String? = null, val destination: String? = null)
data class RideReceipt(
    val fare: Double?, val distance: Double?, val route: RideRoute,
    val reference: String? = null
)

/** Pure parsing: a missing/ambiguous field stays null. No offered price is a receipt. */
object RideReceiptParser {
    const val NUMBER = "(?:[0-9]{1,3}(?:\\.[0-9]{3})+,[0-9]{2}|[0-9]+[,.][0-9]{2}|[0-9]+)(?![0-9.,])"
    val money = Regex("R\\$\\s*($NUMBER)", RegexOption.IGNORE_CASE)
    private val distance = Regex("(?<![0-9.,])([0-9]+(?:[.,][0-9]{1,3})?)\\s*km\\b", RegexOption.IGNORE_CASE)
    private val finished = Regex("\\b(?:corrida|viagem)\\s+(?:finalizada|concluida)\\b|\\bfinalizada com sucesso\\b")
    private val summary = Regex("\\b(?:resumo|recibo|comprovante|detalhes) (?:da )?(?:corrida|viagem)\\b")
    private val net = Regex("^(?:valor liquido|ganho liquido|seus ganhos|voce ganhou|voce recebeu|ganhos? (?:da|desta) (?:corrida|viagem)|recebido (?:nesta|pela) corrida)\\s*[: -]*$")
    private val total = Regex("^(?:valor (?:recebido|da corrida|da viagem|final)|total (?:recebido|da corrida|da viagem))\\s*[: -]*$")
    private val cancelled = Regex("\\b(?:cancelad[ao]|nao realizada|nao concluida)\\b")
    private val offerAction = Regex("\\b(?:aceitar|aceite|recusar|solicitacao|proxima corrida)\\b")

    fun normalized(text: String): String = Normalizer.normalize(text, Normalizer.Form.NFD)
        .replace(Regex("\\p{M}+"), "").lowercase(Locale.ROOT).trim()

    fun number(text: String): Double? = (if (text.contains(',')) text.replace(".", "").replace(',', '.') else text)
        .toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0.0 }

    fun lines(text: String): List<String> = text.replace(" | ", "\n").lines().map(String::trim).filter(String::isNotEmpty)

    fun parse(text: String): RideReceipt? {
        val normalized = normalized(text)
        if (cancelled.containsMatchIn(normalized) || offerAction.containsMatchIn(normalized)) return null
        // Never treat wallet/week totals or a payment collection button as proof of completion.
        if (!finished.containsMatchIn(normalized) && !summary.containsMatchIn(normalized)) return null
        val rows = lines(text)
        val preferred = labeledMoney(rows, net)
        val totals = labeledMoney(rows, total)
        val fare = if (preferred.isNotEmpty()) preferred.distinct().singleOrNull() else totals.distinct().singleOrNull()
        val route = route(text)
        val kms = mutableListOf<Double>()
        for ((index, row) in rows.withIndex()) {
            val n = normalized(row)
            if (!Regex("^(?:distancia(?: percorrida| da corrida| da viagem)?|percurso|trajeto)\\b").containsMatchIn(n)) continue
            val joined = row + " " + (rows.getOrNull(index + 1)?.takeIf { distance.matches(it) } ?: "")
            kms.addAll(distance.findAll(joined).mapNotNull { number(it.groupValues[1]) }.filter { it > 0 })
        }
        val reference = Regex("(?:id|codigo|numero) (?:da )?(?:corrida|viagem)\\s*[:#-]?\\s*([a-z0-9-]{4,64})")
            .find(normalized)?.groupValues?.get(1)
        // A heading alone can be an animation frame. Wait for at least one receipt field.
        if (fare == null && totals.isEmpty() && preferred.isEmpty() && kms.isEmpty() && route.pickup == null && route.destination == null && reference == null) return null
        return RideReceipt(fare, kms.distinct().singleOrNull(), route, reference)
    }

    private fun labeledMoney(rows: List<String>, label: Regex): List<Double> = rows.mapIndexedNotNull { index, row ->
        val match = money.find(row)
        val prefix = if (match != null) row.substring(0, match.range.first).trim() else row
        if (!label.matches(normalized(prefix))) return@mapIndexedNotNull null
        if (match != null) {
            if (money.findAll(row).count() != 1) return@mapIndexedNotNull null
            number(match.groupValues[1])
        } else {
            val next = rows.getOrNull(index + 1) ?: return@mapIndexedNotNull null
            money.matchEntire(next)?.groupValues?.get(1)?.let(::number)
        }
    }

    fun route(text: String): RideRoute {
        val rows = lines(text)
        fun address(label: Regex): String? {
            val values = rows.mapIndexedNotNull { index, row ->
                val match = label.find(normalized(row)) ?: return@mapIndexedNotNull null
                val value = row.drop(match.value.length).trim(' ', ':', '-')
                    .ifEmpty { rows.getOrNull(index + 1).orEmpty() }
                value.takeIf { isAddress(it) }
            }.distinct()
            return values.singleOrNull()
        }
        return RideRoute(
            address(Regex("^(?:local de embarque|endereco de embarque|embarque|origem|partida)\\s*[: -]*")),
            address(Regex("^(?:local de desembarque|endereco de destino|desembarque|destino|chegada)\\s*[: -]*"))
        )
    }

    fun isAddress(value: String): Boolean = value.length in 5..300 && value.any(Char::isLetter) &&
        !value.contains('…') && !value.endsWith("...") && !money.containsMatchIn(value) &&
        !Regex("^(?:aceitar|recusar|total|ganhos|distancia|destino|embarque|origem|desembarque|[0-9]+\\s*min)\\b")
            .containsMatchIn(normalized(value))
}
