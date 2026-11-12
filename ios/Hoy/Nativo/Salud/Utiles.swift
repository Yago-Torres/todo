import SwiftUI
import UIKit

// Lo común de Salud, Pendientes y Documentos: fechas en español, el selector de pastillas y el aviso con «Deshacer».

/// Fechas y cifras como se leen en España. Los días del servidor son «yyyy-MM-dd» (o «yyyy-MM-ddTHH:mm»).
enum FechasES {
    static let locale = Locale(identifier: "es_ES")

    private static var calendario: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = locale
        c.firstWeekday = 2
        c.timeZone = .current
        return c
    }

    /// El día de un texto del servidor, a mediodía (así el cambio de hora no lo mueve de día).
    static func fecha(_ s: String) -> Date? {
        guard s.count >= 10 else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(s.prefix(10))) else { return nil }
        return calendario.date(bySettingHour: 12, minute: 0, second: 0, of: d)
    }

    static func texto(_ d: Date, _ formato: String) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendario
        f.timeZone = .current
        f.dateFormat = formato
        return f.string(from: d)
    }

    static func masDias(_ s: String, _ n: Int) -> String {
        guard let d = fecha(s), let nuevo = calendario.date(byAdding: .day, value: n, to: d) else { return s }
        return Fecha.dia(nuevo)
    }

    /// Días de `a` a `b` (positivo si `b` es después).
    static func entre(_ a: String, _ b: String) -> Int {
        guard let x = fecha(a), let y = fecha(b) else { return 0 }
        return calendario.dateComponents([.day], from: calendario.startOfDay(for: x), to: calendario.startOfDay(for: y)).day ?? 0
    }

    /// «14 nov»
    static func corta(_ s: String) -> String { fecha(s).map { texto($0, "d MMM") } ?? s }
    /// «14 nov 2026»
    static func larga(_ s: String) -> String { fecha(s).map { texto($0, "d MMM yyyy") } ?? s }
    /// «vie 14»
    static func diaSemana(_ s: String) -> String { fecha(s).map { texto($0, "EEE d") } ?? s }

    /// «hoy», «mañana», «vie 14», «3 dic»
    static func cuando(_ s: String) -> String {
        let n = entre(Fecha.hoy(), s)
        switch n {
        case 0: return "hoy"
        case 1: return "mañana"
        case -1: return "ayer"
        case 2...6: return diaSemana(s)
        default: return corta(s)
        }
    }

    /// «hoy», «ayer», «hace 3 días»
    static func hace(_ s: String) -> String {
        let n = entre(s, Fecha.hoy())
        return n <= 0 ? "hoy" : n == 1 ? "ayer" : "hace \(n) días"
    }

    /// 425 minutos → «7 h 05»
    static func hm(_ minutos: Double) -> String {
        let m = Int(minutos.rounded())
        return "\(m / 60) h \(String(format: "%02d", m % 60))"
    }

    /// 8432 → «8.432» (siempre con punto de millares, como en la web)
    static func miles(_ n: Double) -> String {
        let s = String(Int(n.rounded()))
        var out = ""
        for (i, c) in s.reversed().enumerated() {
            if i > 0, i % 3 == 0, c != "-" { out.append(".") }
            out.append(c)
        }
        return String(out.reversed())
    }

    static func coma(_ x: Double, _ decimales: Int = 1) -> String {
        String(format: "%.\(decimales)f", x).replacingOccurrences(of: ".", with: ",")
    }
}

/// Pastillas para elegir una opción: la seleccionada es una gota de acento que se desliza a la siguiente.
struct SelectorPildoras<Valor: Hashable>: View {
    let opciones: [(valor: Valor, titulo: String)]
    @Binding var seleccion: Valor
    @Namespace private var espacio

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Tema.Espacio.s) {
                ForEach(opciones.indices, id: \.self) { i in
                    let o = opciones[i]
                    let activa = o.valor == seleccion
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(Tema.Muelle.pantalla) { seleccion = o.valor }
                    } label: {
                        Text(o.titulo)
                            .font(Tema.fuente(.pequeno, peso: .medium))
                            .foregroundStyle(activa ? Tema.acentoTexto : Tema.suave)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                if activa {
                                    Capsule().fill(Tema.acento).matchedGeometryEffect(id: "pildora", in: espacio)
                                } else {
                                    Capsule().fill(Tema.carta)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(activa ? .isSelected : [])
                }
            }
        }
        .contentMargins(.horizontal, Tema.Espacio.l, for: .scrollContent)
        .scrollIndicators(.hidden)
    }
}

/// Un mensaje breve abajo, con «Deshacer» si se puede.
struct AvisoTom: Identifiable {
    let id = UUID()
    var texto: String
    var error = false
    var deshacer: (@MainActor () async -> Void)?
}

private struct ModificadorTostada: ViewModifier {
    let aviso: AvisoTom?
    let quita: () -> Void

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let aviso {
                HStack(spacing: Tema.Espacio.m) {
                    Image(systemName: aviso.error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(aviso.error ? Tema.peligro : Tema.acento)
                    Text(aviso.texto)
                        .font(Tema.fuente(.pequeno))
                        .foregroundStyle(Tema.texto)
                        .lineLimit(3)
                    Spacer(minLength: Tema.Espacio.s)
                    if let deshacer = aviso.deshacer {
                        Button("Deshacer") {
                            quita()
                            Task { await deshacer() }
                        }
                        .font(Tema.fuente(.pequeno, peso: .semibold))
                        .foregroundStyle(Tema.acento)
                    }
                }
                .padding(Tema.Espacio.m)
                .background(Tema.carta, in: RoundedRectangle(cornerRadius: Tema.Radio.carta, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Tema.Radio.carta, style: .continuous)
                    .strokeBorder(Tema.linea, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .padding(.horizontal, Tema.Espacio.l)
                .padding(.bottom, 96)   // por encima de la barra
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: aviso.id) {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if !Task.isCancelled { quita() }
                }
            }
        }
        .animation(Tema.Muelle.pantalla, value: aviso?.id)
    }
}

extension View {
    func tostada(_ aviso: AvisoTom?, quita: @escaping () -> Void) -> some View {
        modifier(ModificadorTostada(aviso: aviso, quita: quita))
    }
}

/// El campo de búsqueda de las listas, con el estilo del tema.
struct CampoBusqueda: View {
    @Binding var texto: String
    var pista = "Buscar"

    var body: some View {
        HStack(spacing: Tema.Espacio.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(Tema.suave)
            TextField(pista, text: $texto)
                .font(Tema.fuente(.texto))
                .foregroundStyle(Tema.texto)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !texto.isEmpty {
                Button {
                    texto = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Tema.tenue)
                }
                .accessibilityLabel("Borrar la búsqueda")
            }
        }
        .padding(.horizontal, Tema.Espacio.m)
        .padding(.vertical, 10)
        .background(Tema.carta, in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous)
            .strokeBorder(Tema.linea.opacity(0.6), lineWidth: 0.5))
    }
}

extension String {
    /// Contiene `buscado` sin mirar mayúsculas ni tildes.
    func contieneBusqueda(_ buscado: String) -> Bool {
        buscado.isEmpty || range(of: buscado, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
