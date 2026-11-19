import SwiftUI

// Lo del 19/11 (como la web): el informe de mercado del sábado (mercado.py), el modo «no mires» (las cifras de la cartera
// solo el día de mirar) y las multas por hábitos (cada hábito sin hacer suma a lo que toca invertir).

struct MultasConfInv: Codable, Equatable {
    var activo = false
    var fallo: Double = 1
    var racha: Double = 5
    var rachaMin = 3
    var desde = ""

    enum CodingKeys: String, CodingKey { case activo, fallo, racha, desde, rachaMin = "racha_min" }

    var crudo: [String: Any] { ["activo": activo, "fallo": fallo, "racha": racha, "racha_min": rachaMin, "desde": desde] }
}

struct MultaInv: Decodable, Hashable {
    var dia: String
    var id: String
    var n: String
    var euros: Double
    var motivo: String
}

struct RespuestaMultas: Decodable {
    var conf: MultasConfInv
    var multas: [MultaInv]
    var total: Double
    var hayHabito: Bool

    enum CodingKeys: String, CodingKey { case conf, multas, total, hayHabito = "hay_habito" }
}

struct EventoMercado: Decodable, Hashable, Identifiable {
    var id: String
    var dia: String
    var hora: String
    var t: String
    var tipo: String
    var nota: String
}

struct RespuestaMercado: Decodable {
    struct Informe: Decodable { var fecha: String; var texto: String }
    var fechas: [String]
    var ultimo: Informe?
    var eventos: [EventoMercado]
}

extension DatosInversiones {
    /// Cambia solo esas claves del perfil (el servidor mezcla lo que llega con lo que había).
    func guardaPerfilParcial(_ cambios: [String: Any], _ ok: String) async -> Bool {
        do {
            _ = try await API.datos("/api/inversiones/perfil", metodo: "POST", json: cambios)
            Haptica.shared.toca(.marcar)
            avisa(ok)
            await carga()
            return true
        } catch {
            avisa("No se ha guardado: \(error.localizedDescription)", error: true)
            return false
        }
    }

    func multas() async -> RespuestaMultas? {
        guard let r = try? await API.leeOCopia("/api/multas") else { return nil }
        return try? JSONDecoder().decode(RespuestaMultas.self, from: r.datos)
    }

    func creaHabitoAportar() async {
        do {
            _ = try await API.datos("/api/habito/aportar", metodo: "POST", json: [String: Any]())
            avisa("Hábito creado: lo marcan solas tus compras")
        } catch {
            avisa("No se ha podido: \(error.localizedDescription)", error: true)
        }
    }

    func mercado() async -> RespuestaMercado? {
        guard let r = try? await API.leeOCopia("/api/mercado") else { return nil }
        return try? JSONDecoder().decode(RespuestaMercado.self, from: r.datos)
    }

    func informeMercado(_ fecha: String) async -> String? {
        struct T: Decodable { var texto: String }
        guard let r = try? await API.leeOCopia("/api/mercado/\(fecha)") else { return nil }
        return (try? JSONDecoder().decode(T.self, from: r.datos))?.texto
    }
}

// MARK: Mercado

struct MercadoInversiones: View {
    @State private var datos = DatosInversiones.shared
    @State private var m: RespuestaMercado?
    @State private var cargado = false
    @State private var fecha = ""
    @State private var texto: String?

    private static let tipos = ["bce": "BCE", "fed": "Fed", "resultados": "Resultados", "dato": "Dato"]

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.l) {
            VStack(alignment: .leading, spacing: Tema.Espacio.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text(fecha.isEmpty ? "Informe de mercado" : "Informe · \(FechasES.corta(fecha))")
                        .font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                    Spacer()
                    if let m, m.fechas.count > 1 {
                        Menu {
                            ForEach(m.fechas, id: \.self) { f in
                                Button("Semana del \(FechasES.corta(f))") { Task { await abre(f) } }
                            }
                        } label: {
                            Label("Otras", systemImage: "calendar").font(Tema.fuente(.pequeno, peso: .semibold))
                        }
                        .tint(Tema.acento)
                    }
                }
                if let texto {
                    MarkdownInv(texto: texto)
                } else {
                    Text(cargado ? "Todavía no hay informe: sale los sábados por la mañana." : "Cargando…")
                        .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .carta()

            if let ev = m?.eventos, !ev.isEmpty {
                VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                    Text("Lo que viene").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                    Text("También en el calendario, en «Mercados» (con su interruptor).")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    ForEach(ev) { e in
                        HStack(alignment: .firstTextBaseline, spacing: Tema.Espacio.m) {
                            Text(FechasES.corta(e.dia) + (e.hora.isEmpty ? "" : " \(e.hora)"))
                                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).monospacedDigit()
                                .frame(width: 84, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.t).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                                if !e.nota.isEmpty {
                                    Text(e.nota).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .carta()
            }
        }
        .task {
            m = await datos.mercado()
            cargado = true
            if let u = m?.ultimo { fecha = u.fecha; texto = u.texto }
        }
    }

    private func abre(_ f: String) async {
        if f == m?.ultimo?.fecha { fecha = f; texto = m?.ultimo?.texto; return }
        if let t = await datos.informeMercado(f) {
            withAnimation(Tema.Muelle.pantalla) { fecha = f; texto = t }
        }
    }
}

// MARK: «no mires»

/// Arriba de Cartera fuera del día de mirar: las cifras se tapan hasta que pides verlas.
struct NoMiresInvCarta: View {
    let perfil: PerfilInv
    let alVer: () -> Void

    private static let dias = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Label("Hoy no toca mirar", systemImage: "eye.slash").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
            Text("Modo «no mires»: la cartera se mira el \(Self.dias[min(6, max(0, perfil.diaMirar ?? 6))]). "
                 + "Lo que pase en un día no dice nada a \(perfil.horizonte.isEmpty ? "largo plazo" : perfil.horizonte).")
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                .fixedSize(horizontal: false, vertical: true)
            Button("Ver igualmente", action: alVer)
                .font(Tema.fuente(.pequeno, peso: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Tema.acentoSuave, in: Capsule())
                .foregroundStyle(Tema.acento)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .carta()
    }
}

/// En Perfil: el interruptor y el día. Se guarda al tocar.
struct NoMiresInvAjuste: View {
    let perfil: PerfilInv
    @State private var datos = DatosInversiones.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Toggle(isOn: Binding(get: { perfil.noMires ?? false }, set: { v in
                Task { _ = await datos.guardaPerfilParcial(["no_mires": v], v ? "Modo «no mires» activado" : "Modo «no mires» quitado") }
            })) {
                Text("Modo «no mires»").font(Tema.fuente(.destacado, peso: .semibold)).foregroundStyle(Tema.texto)
            }
            .tint(Tema.acento)
            Text("El valor y lo que sube o baja cada día solo se ven el día que elijas, y las alertas de caída no avisan.")
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                .fixedSize(horizontal: false, vertical: true)
            if perfil.noMires ?? false {
                Picker("Día de mirar", selection: Binding(get: { perfil.diaMirar ?? 6 }, set: { d in
                    Task { _ = await datos.guardaPerfilParcial(["dia_mirar": d], "Día de mirar guardado") }
                })) {
                    ForEach(Array(["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"].enumerated()), id: \.offset) { i, n in
                        Text(n).tag(i)
                    }
                }
                .pickerStyle(.menu)
                .tint(Tema.acento)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .carta()
    }
}

// MARK: multas

struct MultasInvCarta: View {
    let perfil: PerfilInv
    @State private var datos = DatosInversiones.shared
    @State private var r: RespuestaMultas?
    @State private var fallo = ""
    @State private var racha = ""
    @State private var rachaMin = 3

    private var conf: MultasConfInv { perfil.multas ?? MultasConfInv() }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Text("Multas por hábitos").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
            Text("Cada hábito que te saltas suma a lo que toca invertir este ciclo (en Gastos); romper una racha, más. Un comodín que la salva no multa.")
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Activadas", isOn: Binding(get: { conf.activo }, set: { v in guarda(activo: v) }))
                .tint(Tema.acento)
            if conf.activo {
                fila("Por hábito sin hacer (€)", $fallo)
                fila("Por romper una racha (€ más)", $racha)
                Stepper("Racha desde \(rachaMin) días", value: $rachaMin, in: 1...60)
                    .font(Tema.fuente(.texto))
                Button("Guardar importes") { guarda(activo: true) }
                    .font(Tema.fuente(.pequeno, peso: .semibold)).tint(Tema.acento)
                if let r {
                    Divider().overlay(Tema.linea)
                    Text(r.multas.isEmpty ? "Desde el \(FechasES.corta(conf.desde)): ni una multa. Así sí."
                                          : "Desde el \(FechasES.corta(conf.desde)): \(DineroES.eur(r.total)) en multas.")
                        .font(Tema.fuente(.texto, peso: .medium)).foregroundStyle(Tema.texto)
                    ForEach(Array(r.multas.reversed().prefix(8).enumerated()), id: \.offset) { _, x in
                        HStack(alignment: .firstTextBaseline) {
                            Text(FechasES.corta(x.dia)).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).frame(width: 52, alignment: .leading)
                            Text("\(x.n): \(x.motivo)").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.texto)
                            Spacer()
                            Text(DineroES.eur(x.euros)).font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.texto)
                        }
                    }
                }
            }
            if let r, !r.hayHabito {
                Divider().overlay(Tema.linea)
                Text("Aportar como hábito: se marca solo el día que compras algo (también los planes) y lleva su racha.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Crear el hábito «Aportar a la inversión»") {
                    Task { await datos.creaHabitoAportar(); self.r = await datos.multas() }
                }
                .font(Tema.fuente(.pequeno, peso: .semibold)).tint(Tema.acento)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .carta()
        .task(id: conf) {
            fallo = DineroES.campo(conf.fallo)
            racha = DineroES.campo(conf.racha)
            rachaMin = conf.rachaMin
            r = await datos.multas()
        }
    }

    private func fila(_ titulo: String, _ texto: Binding<String>) -> some View {
        HStack {
            Text(titulo).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
            Spacer()
            TextField("0", text: texto)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
                .padding(.horizontal, Tema.Espacio.m).padding(.vertical, 6)
                .frame(width: 90)
                .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
        }
    }

    private func guarda(activo: Bool) {
        var c = conf
        c.fallo = DineroES.numero(fallo) ?? c.fallo
        c.racha = DineroES.numero(racha) ?? c.racha
        c.rachaMin = rachaMin
        if activo && (!c.activo || c.desde.isEmpty) { c.desde = Fecha.hoy() }   // las multas cuentan desde que se activan
        if !activo { c.desde = "" }
        c.activo = activo
        Task { _ = await datos.guardaPerfilParcial(["multas": c.crudo], activo ? "Multas guardadas" : "Multas desactivadas") }
    }
}
