// Prueba de la lógica pura de Compartido/Operaciones.swift (aplicar operaciones de la cola a un estado de ejemplo).
// No va en ningún target ni en CI. En un Mac, desde ios/:
//
//   swiftc -D PRUEBA Compartido/Operaciones.swift Pruebas/PruebaOperaciones.swift Pruebas/Apoyo.swift -o /tmp/prueba && /tmp/prueba
//
// Apoyo.swift (no está en el repo) solo tiene que dar lo que la extensión «con la base local» usa (Local, Almacen); la parte probada aquí no
// lo toca. Sin Mac: se lee como lista de casos revisados a mano.

import Foundation

private var fallos = 0

private func comprueba(_ cond: Bool, _ que: String) {
    if cond { print("ok   \(que)") } else { fallos += 1; print("MAL  \(que)") }
}

private func habitos(_ e: [String: Any]) -> [[String: Any]] { (e["habits"] as? [[String: Any]]) ?? [] }

@main
enum PruebaOperaciones {
    static func main() {
        // el servidor (el bot ha creado «agua» y planificado «leer» mientras el iPhone estaba sin red)
        var servidor: [String: Any] = [
            "habits": [["id": "leer", "n": "Leer", "c": "#111111", "goal": 7, "cada": 1],
                       ["id": "agua", "n": "Agua", "c": "#222222", "goal": 7, "cada": 1]],
            "log": ["2026-11-12": ["leer"]],
            "plan": ["2026-11-13": ["leer"]],
            "rutinas": [["id": "r1"]],
        ]

        // 1. editar un campo cualquiera (también uno que la app no conoce: descansos) no toca lo demás
        try? Operaciones.aplicaEstado(["op": "habito.edita", "id": "leer",
                                       "cambios": ["n": "Leer 20 min", "descansos": ["2026-11-20"]]],
                                      &servidor, estricto: true)
        let leer = habitos(servidor).first { ($0["id"] as? String) == "leer" }
        comprueba(leer?["n"] as? String == "Leer 20 min", "edita el nombre")
        comprueba((leer?["descansos"] as? [String]) == ["2026-11-20"], "acepta campos nuevos")
        comprueba(leer?["c"] as? String == "#111111", "conserva el color")
        comprueba(habitos(servidor).count == 2, "no pisa el hábito que creó el bot")
        comprueba((servidor["rutinas"] as? [[String: Any]])?.count == 1, "no toca las rutinas")

        // 2. NSNull quita el campo
        try? Operaciones.aplicaEstado(["op": "habito.edita", "id": "leer", "cambios": ["descansos": NSNull()]],
                                      &servidor, estricto: true)
        comprueba(habitos(servidor).first?["descansos"] == nil, "NSNull quita el campo")

        // 3. crear es idempotente (si la respuesta se perdió y sale otra vez, no se duplica)
        let crea: [String: Any] = ["op": "habito.crea", "id": "core", "campos": ["id": "core", "n": "Core", "goal": 3]]
        try? Operaciones.aplicaEstado(crea, &servidor, estricto: true)
        try? Operaciones.aplicaEstado(crea, &servidor, estricto: true)
        comprueba(habitos(servidor).filter { ($0["id"] as? String) == "core" }.count == 1, "crear dos veces deja uno")

        // 4. planificar se suma a lo que planificó el bot
        try? Operaciones.aplicaEstado(["op": "plan.pon", "id": "core", "dia": "2026-11-13", "si": true], &servidor, estricto: true)
        comprueba(((servidor["plan"] as? [String: Any])?["2026-11-13"] as? [String]) == ["leer", "core"], "plan: suma, no reemplaza")

        // 5. editar algo que el bot borró: rechazo con texto claro (en local, sin más)
        var sinAgua = servidor
        try? Operaciones.aplicaEstado(["op": "habito.borra", "id": "agua"], &sinAgua, estricto: true)
        var rechazo: String?
        do {
            try Operaciones.aplicaEstado(["op": "habito.edita", "id": "agua", "cambios": ["n": "Beber"]], &sinAgua, estricto: true)
        } catch let r as Operaciones.Rechazo { rechazo = r.mensaje } catch {}
        comprueba(rechazo?.contains("ya no existe") == true, "editar un hábito borrado: rechazo")
        var copia = sinAgua
        comprueba((try? Operaciones.aplicaEstado(["op": "habito.edita", "id": "agua", "cambios": ["n": "x"]], &copia, estricto: false)) != nil,
                  "en local no falla")

        // 6. borrar se lleva su log y su plan
        try? Operaciones.aplicaEstado(["op": "habito.borra", "id": "leer"], &servidor, estricto: true)
        comprueba((servidor["log"] as? [String: Any])?["2026-11-12"] == nil, "borrar limpia el log")

        // 7. gastos: editar uno, borrar otro (idempotente) y presupuesto
        var gastos: [String: Any] = ["gastos": [["id": "a", "importe": 10.0, "cat": "comida"], ["id": "b", "importe": 5.0]],
                                     "cats": [["id": "comida", "presu": 200.0]]]
        try? Operaciones.aplicaGastos(["op": "gasto.edita", "id": "a", "cambios": ["importe": 12.5]], &gastos, estricto: true)
        try? Operaciones.aplicaGastos(["op": "gasto.borra", "id": "b"], &gastos, estricto: true)
        try? Operaciones.aplicaGastos(["op": "gasto.borra", "id": "b"], &gastos, estricto: true)
        try? Operaciones.aplicaGastos(["op": "presupuesto.pon", "valores": ["comida": 250.0]], &gastos, estricto: true)
        let g = (gastos["gastos"] as? [[String: Any]]) ?? []
        comprueba(g.count == 1 && (g[0]["importe"] as? Double) == 12.5, "gasto editado y otro borrado")
        comprueba(((gastos["cats"] as? [[String: Any]])?.first?["presu"] as? Double) == 250, "presupuesto puesto")

        // 8. tareas: creada sin red (tmp), cambiada y hecha; con el alias tmp → real ya conocido
        var bandeja: [String: Any] = ["tareas": [["id": "real1", "t": "Llamar"]]]
        let alias: (String) -> String = { $0 == "tmp:X" ? "real2" : $0 }
        func p(_ ruta: String, _ cuerpo: [String: Any], _ cab: [String: String] = [:]) -> Operaciones.Pendiente {
            Operaciones.Pendiente(metodo: "POST", ruta: ruta, cuerpo: cuerpo, cabeceras: cab)
        }
        try? Operaciones.aplica(p("/api/tarea", ["t": "Comprar pan"], ["x-tom-tmp": "tmp:X"]), en: "/api/bandeja", &bandeja, alias: alias)
        try? Operaciones.aplica(p("/api/tarea/edita", ["id": "tmp:X", "t": "Comprar pan y leche", "due": "2026-11-14"]),
                                en: "/api/bandeja", &bandeja, alias: alias)
        let ts = (bandeja["tareas"] as? [[String: Any]]) ?? []
        comprueba(ts.count == 2 && (ts[1]["id"] as? String) == "real2" && (ts[1]["t"] as? String) == "Comprar pan y leche",
                  "tarea provisional: aparece con su id real y cambiada")
        try? Operaciones.aplica(p("/api/tarea/hecha", ["id": "real1", "hecha": true]), en: "/api/bandeja", &bandeja, alias: alias)
        comprueba(((bandeja["tareas"] as? [[String: Any]]) ?? []).count == 1, "tarea hecha se va de la lista")

        print(fallos == 0 ? "Todo bien" : "\(fallos) fallos")
        exit(fallos == 0 ? 0 : 1)
    }
}
