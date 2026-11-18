import SwiftUI

/// La pestaña Perfil: tu contexto para la review del domingo. Lo que quede vacío, la review lo supone y lo pregunta.
struct PerfilInversiones: View {
    let perfil: PerfilInv
    @State private var datos = DatosInversiones.shared
    @State private var p = PerfilInv()
    @State private var edad = ""
    @State private var aportacion = ""
    @State private var perdidas = ""
    @State private var intereses = ""

    /// La declaración en la que estás: los intereses que se apuntan son de ese año.
    private var ejercicio: String { String(datos.inf?.declaracion?.ejercicio ?? Calendar.current.component(.year, from: Date())) }

    private func conCampos(_ base: PerfilInv) -> PerfilInv {
        var x = base
        x.edad = Int(edad.trimmingCharacters(in: .whitespaces))
        x.aportacion = DineroES.numero(aportacion) ?? 0
        x.perdidasPrevias = DineroES.numero(perdidas) ?? 0
        var i = perfil.intereses ?? [:]
        if let n = DineroES.numero(intereses), n > 0 { i[ejercicio] = n } else { i[ejercicio] = nil }
        x.intereses = i
        return x
    }
    @State private var guardando = false

    private var cambiado: Bool {
        conCampos(p) != perfil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.l) {
            Text("Lo lee la review del domingo. Lo que dejes vacío lo supondrá y te lo preguntará.")
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                .fixedSize(horizontal: false, vertical: true)

            grupo("Tú") {
                campo("Edad", "años", $edad, numero: true)
                campo("Aportación mensual (€)", "200", $aportacion, numero: true)
                eleccion("¿Es estable?", [(nil, "Sin decir"), (true, "Sí"), (false, "No")], $p.estable)
                campo("Fondo de emergencia", "Sí, 6 meses de gastos", $p.emergencia)
            }
            grupo("Objetivo y riesgo") {
                campo("Horizonte", "10+ años", $p.horizonte)
                campoLargo("Objetivo", "Crecimiento a largo plazo, entrada de un piso en 2032…", $p.objetivo)
                eleccion("Tolerancia al riesgo", [("", "Sin decir"), ("baja", "Baja"), ("media", "Media"), ("alta", "Alta")], $p.tolerancia)
                campo("Caída que aguantarías sin vender", "-30 %", $p.caida)
            }
            grupo("Cuentas") {
                campo("Broker(s)", "Trade Republic", $p.broker)
                campo("Referencia para comparar", "VWCE.DE", $p.referencia, mayusculas: true)
            }
            grupo("Impuestos") {
                eleccion("Dónde tributas", [("comun", "Régimen común"), ("foral", "Navarra o País Vasco")],
                         Binding(get: { p.regimen ?? "comun" }, set: { p.regimen = $0 }))
                campo("Intereses de la cuenta en \(ejercicio) (€)", "0", $intereses, numero: true)
                campo("Pérdidas de años anteriores (€)", "0", $perdidas, numero: true)
            }
            grupo("Notas para el analista") {
                TextField("Un gasto grande previsto, que no quieres cripto…", text: $p.notas, axis: .vertical)
                    .lineLimit(3...6)
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                    .padding(.vertical, 6)
            }

            Button(action: guarda) {
                HStack {
                    if guardando { ProgressView().tint(Tema.acentoTexto) }
                    Text(guardando ? "Guardando…" : cambiado ? "Guardar" : "Guardado")
                }
                .font(Tema.fuente(.texto, peso: .semibold))
                .foregroundStyle(Tema.acentoTexto)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(cambiado ? Tema.acento : Tema.tenue, in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!cambiado || guardando)
        }
        .onAppear(perform: rellena)
        .onChange(of: perfil) { _, _ in rellena() }
    }

    private func rellena() {
        p = perfil
        edad = perfil.edad.map(String.init) ?? ""
        aportacion = DineroES.campo(perfil.aportacion)
        perdidas = (perfil.perdidasPrevias ?? 0) == 0 ? "" : DineroES.campo(perfil.perdidasPrevias)
        intereses = perfil.intereses?[ejercicio].map { DineroES.campo($0) } ?? ""
    }

    private func guarda() {
        guard !guardando else { return }
        guardando = true
        var x = conCampos(p)
        x.referencia = x.referencia.trimmingCharacters(in: .whitespaces).uppercased()
        Task {
            _ = await datos.guardaPerfil(x)
            guardando = false
        }
    }

    // MARK: piezas

    private func grupo<Contenido: View>(_ titulo: String, @ViewBuilder _ contenido: () -> Contenido) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(titulo).estiloEtiqueta().foregroundStyle(Tema.suave).padding(.bottom, Tema.Espacio.s)
            contenido()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .carta()
    }

    private func campo(_ titulo: String, _ pista: String, _ texto: Binding<String>, numero: Bool = false,
                       mayusculas: Bool = false) -> some View {
        HStack(spacing: Tema.Espacio.m) {
            Text(titulo).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
            Spacer(minLength: Tema.Espacio.s)
            TextField(pista, text: texto)
                .font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                .multilineTextAlignment(.trailing)
                .keyboardType(numero ? .decimalPad : .default)
                .textInputAutocapitalization(mayusculas ? .characters : .sentences)
                .autocorrectionDisabled(mayusculas)
                .frame(maxWidth: 190)
        }
        .padding(.vertical, 8)
    }

    private func campoLargo(_ titulo: String, _ pista: String, _ texto: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
            TextField(pista, text: texto, axis: .vertical)
                .lineLimit(1...3)
                .font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
        }
        .padding(.vertical, 8)
    }

    private func eleccion<V: Hashable>(_ titulo: String, _ opciones: [(V, String)], _ valor: Binding<V>) -> some View {
        HStack(spacing: Tema.Espacio.m) {
            Text(titulo).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
            Spacer(minLength: Tema.Espacio.s)
            Picker(titulo, selection: valor) {
                ForEach(Array(opciones.enumerated()), id: \.offset) { _, o in Text(o.1).tag(o.0) }
            }
            .labelsHidden()
            .tint(Tema.acento)
        }
        .padding(.vertical, 4)
    }
}
