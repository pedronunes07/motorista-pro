package com.motoristapro.app

private fun expect(value: Boolean, message: String) { check(value) { message } }
private fun close(a: Double?, b: Double) = a != null && kotlin.math.abs(a - b) < 0.000001

fun main() {
    var cases = 0
    fun test(name: String, run: () -> Unit) { run(); cases++; println("PASS $name") }
    test("dot/comma currency never matches a prefix") {
        for ((text,value) in listOf("26.25" to 26.25,"4,60" to 4.60,"1.234,56" to 1234.56,"2,50" to 2.5,"0,00" to 0.0)) {
            expect(close(RideReceiptParser.parse("Corrida finalizada\nValor recebido: R$ $text")?.fare,value),text)
        }
        expect(RideReceiptParser.parse("Corrida finalizada\nValor recebido: R$ 26.250") == null,"ambiguous thousands must not truncate")
    }
    test("cash collection, wallet and cancelled rides are not receipts") {
        for (text in listOf("Total recebido R$ 200,00","Você ganhou R$ 200,00","Valor líquido R$ 100,00","Corrida cancelada\nValor recebido R$ 5,00","Corrida encerrada\nCobrar do passageiro R$ 18,50")) expect(RideReceiptParser.parse(text)==null,text)
        expect(RideReceiptParser.parse("Corrida finalizada\nCobrar do passageiro R$ 18,50")==null,"cash is not net fare")
    }
    test("net receipt wins over gross, fees and change") {
        val receipt = RideReceiptParser.parse("Resumo da viagem\nValor da viagem R$ 30,00\nValor líquido\nR$ 26.25\nTaxa R$ 3,75\nTroco R$ 9,00")!!
        expect(close(receipt.fare,26.25),"net fare")
        expect(receipt.distance==null,"missing distance")
    }
    test("conflicting receipt totals stay unknown") {
        val receipt=RideReceiptParser.parse("Corrida concluída\nValor recebido R$ 20,00\nValor recebido R$ 28,00")!!
        expect(receipt.fare==null,"must not choose first total")
    }
    test("final receipt addresses and traveled distance") {
        val receipt=RideReceiptParser.parse("Viagem concluída\nValor recebido: R$ 26.25\nDistância percorrida: 8,4 km\nEmbarque: Rua A, 100, Recife - PE\nDestino\nRua B, 200, Recife - PE")!!
        expect(close(receipt.distance,8.4),"distance")
        expect(receipt.route.pickup=="Rua A, 100, Recife - PE","pickup")
        expect(receipt.route.destination=="Rua B, 200, Recife - PE","destination")
    }
    test("unlabeled screen kilometers never become traveled distance") {
        expect(RideReceiptParser.parse("Corrida finalizada\nValor recebido R$ 26,25\n8,4 km")!!.distance==null,"no implicit distance")
    }
    test("99 offer from user reference") {
        val offer=ScreenOfferParser.parse("Moto\nR$4,60\n0% de Taxa99 semanal\n4,78 +999 corridas\nPerfil Premium\n6 min (1,8 km)\nRua Delmiro da Silva, 240,\nBonsucesso\n4 min (1,6 km)\nCentro Municipal de Educação\nAceitar")!!
        expect(close(offer.fare,4.6) && close(offer.distance,3.4) && offer.minutes==10,"offer arithmetic")
        expect(offer.route.pickup=="Rua Delmiro da Silva, 240, Bonsucesso","pickup rows")
        expect(offer.route.destination=="Centro Municipal de Educação","destination rows")
    }
    test("equal pickup/trip segments are both counted") {
        val offer=ScreenOfferParser.parse("R$ 26.25\n6 min (1,8 km)\nRua A, 1\n6 min (1,8 km)\nRua B, 2\nAceitar")!!
        expect(close(offer.distance,3.6) && offer.minutes==12,"equal segments")
    }
    test("two separate offers cannot become one") {
        expect(ScreenOfferParser.parse("R$ 15,00\n5 min 2 km\nAceitar\nR$ 25,00\n10 min 4 km\nAceitar")==null,"multiple prices")
    }
    test("receipt without distance is saved without offer estimates") {
        val ledger=RideLedger(); ledger.offer("99",ScreenOffer(30.0,12.0,20,null,RideRoute("Rua A, 1","Rua B, 2")),1000)
        ledger.accept("99",1100)
        val record=ledger.receipt("99",RideReceipt(26.25,null,RideRoute()),2000)
        expect(close(record.value,26.25) && record.distance==null,"receipt does not inherit estimate")
        expect(record.pickup=="Rua A, 1" && record.routeSource=="accepted_offer","accepted route is labeled")
    }
    test("missing fare saves partial record and enriches same ID") {
        val ledger=RideLedger()
        val first=ledger.receipt("99",RideReceipt(null,4.0,RideRoute(),"trip123"),1000)
        val second=ledger.receipt("99",RideReceipt(12.75,4.0,RideRoute("Rua A, 1","Rua B, 2"),"trip123"),2000)
        expect(first.id==second.id && ledger.records.size==1 && second.revision==2,"enrichment")
    }
    test("peek and old acknowledgement preserve newer delivery") {
        val ledger=RideLedger()
        val first=ledger.receipt("99",RideReceipt(12.75,null,RideRoute(),"trip123"),1000)
        expect(ledger.pending().size==1 && ledger.pending().size==1,"peek never drains")
        val second=ledger.receipt("99",RideReceipt(12.75,4.0,RideRoute(),"trip123"),2000)
        ledger.acknowledge(first.id,first.revision)
        expect(ledger.pending().single().revision==2,"old ack")
        ledger.acknowledge(second.id,second.revision)
        expect(ledger.pending().isEmpty(),"new ack")
    }
    test("repeated receipt after acknowledgement does not duplicate") {
        val ledger=RideLedger()
        val receipt=RideReceipt(12.75,4.0,RideRoute(),"trip123")
        val first=ledger.receipt("99",receipt,1000); ledger.acknowledge(first.id,first.revision)
        ledger.receipt("99",receipt,60_000)
        expect(ledger.records.size==1 && ledger.pending().isEmpty(),"repeated OCR")
    }
    test("queued ride never substitutes completed ride") {
        val ledger=RideLedger()
        ledger.offer("99",ScreenOffer(30.0,12.0,20,null,RideRoute("Rua A, 1","Rua B, 2")),1000); ledger.accept("99",1100)
        ledger.offer("99",ScreenOffer(40.0,13.0,20,null,RideRoute("Rua C, 1","Rua D, 2")),1200); ledger.accept("99",1300)
        val first=ledger.receipt("99",RideReceipt(26.25,null,RideRoute()),2000)
        val again=ledger.receipt("99",RideReceipt(26.25,null,RideRoute()),3000)
        expect(first.id==again.id && again.pickup=="Rua A, 1","old receipt consumes next ride")
        ledger.started("99",4000)
        val second=ledger.receipt("99",RideReceipt(37.0,10.0,RideRoute()),5000)
        expect(first.id!=second.id && second.pickup=="Rua C, 1","queue promotion")
    }
    test("conflicting OCR amounts are flagged rather than overwritten") {
        val ledger=RideLedger()
        ledger.receipt("99",RideReceipt(26.25,4.0,RideRoute(),"trip123"),1000)
        val record=ledger.receipt("99",RideReceipt(262.5,4.0,RideRoute(),"trip123"),2000)
        expect(record.value==null && record.conflict,"conflicting prices")
    }
    test("two distinct references can finish within twenty seconds") {
        val ledger=RideLedger()
        ledger.receipt("99",RideReceipt(26.25,null,RideRoute(),"trip123"),1000)
        ledger.receipt("99",RideReceipt(26.25,null,RideRoute(),"trip456"),2000)
        expect(ledger.records.size==2,"no global cooldown")
    }
    test("package provenance rejects unrelated apps") {
        expect(ScreenOfferParser.platformForPackage("com.example.fake99")==null,"broad package match")
        expect(ScreenOfferParser.platformForPackage("com.taxis99")=="99","99 package")
    }
    test("an unaccepted candidate cannot supply a completed route") {
        val ledger=RideLedger()
        ledger.offer("99",ScreenOffer(30.0,12.0,20,null,RideRoute("Rua incorreta, 1","Rua incorreta, 2")),1000)
        ledger.started("99",1500)
        val record=ledger.receipt("99",RideReceipt(26.25,null,RideRoute()),2000)
        expect(record.pickup==null && record.destination==null,"do not infer acceptance")
    }
    test("old receipt cannot borrow route from a new active trip") {
        val ledger=RideLedger()
        val receipt=RideReceipt(26.25,null,RideRoute(),"old123")
        ledger.receipt("99",receipt,1000)
        ledger.offer("99",ScreenOffer(30.0,12.0,20,null,RideRoute("Rua nova, 1","Rua nova, 2")),2000); ledger.accept("99",2500)
        val old=ledger.receipt("99",receipt,3000)
        expect(old.pickup==null && ledger.active.containsKey("99"),"unrelated historical receipt")
    }
    test("area alerts require fresh evidence matching the exact address") {
        val now=1_800_000_000_000L
        val evidence=RiskEvidence("Rua A, 1, Recife PE","BR","Fonte de teste","https://example.org/test",now-1000,now+1000,true)
        expect(RouteRisk.accepts(evidence.address,evidence,now),"valid test evidence")
        expect(!RouteRisk.accepts("Rua B, 1",evidence,now),"wrong route")
        expect(!RouteRisk.accepts(evidence.address,evidence.copy(updatedAt=now-RouteRisk.MAX_AGE-1),now),"stale")
        expect(!RouteRisk.accepts(evidence.address,evidence.copy(expiresAt=now),now),"expired")
        expect(!RouteRisk.accepts(evidence.address,evidence.copy(source=""),now),"no source")
    }
    test("new receipt after leaving the old screen is a separate ride") {
        val ledger=RideLedger()
        ledger.receipt("99",RideReceipt(26.25,null,RideRoute()),1000)
        ledger.noReceipt("99",7000)
        ledger.receipt("99",RideReceipt(18.75,null,RideRoute()),10000)
        expect(ledger.records.size==2,"missed active screen must not merge receipts")
    }
    println("$cases native behavioral tests passed")
}
