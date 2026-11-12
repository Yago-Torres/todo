import SwiftUI
import WidgetKit
import AppIntents

// Piezas comunes de los widgets nuevos: colores según cómo los pinte iOS, el marco con fondo, la casilla interactiva
// y la leyenda. Los colores salen de Paleta (Anillos.swift), que lee la apariencia elegida del app group.

func esAccesorio(_ f: WidgetFamily) -> Bool {
    switch f {
    case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
    default: return false
    }
}

/// Los colores de un widget. A todo color (pantalla de inicio) usa la paleta de Tom; con el tinte de iOS 18, en StandBy
/// nocturno o en la pantalla de bloqueo (accented/vibrant) solo primario y secundario, que el sistema recolorea.
struct Tinta {
    let completo: Bool

    init(_ modo: WidgetRenderingMode) { completo = modo == .fullColor }

    var texto: Color { completo ? Paleta.texto : .primary }
    var suave: Color { completo ? Paleta.suave : .secondary }
    var habitos: Color { completo ? Paleta.hab : .primary }
    var pasos: Color { completo ? Paleta.pas : .primary }
    var sueno: Color { completo ? Paleta.sue : .primary }
    var aviso: Color { completo ? Paleta.aviso : .primary }
    var campo: Color { completo ? Paleta.campo : Color.primary.opacity(0.18) }
}

/// Fondo de Tom (o el de accesorio) y a qué sección abre un toque fuera de los botones.
struct MarcoWidget: ViewModifier {
    @Environment(\.widgetFamily) private var familia
    let ruta: String

    func body(content: Content) -> some View {
        content
            .widgetURL(rutaURL(ruta))
            .containerBackground(for: .widget) {
                if esAccesorio(familia) { AccessoryWidgetBackground() } else { Paleta.fondo }
            }
    }
}

extension View {
    func marcoWidget(_ ruta: String) -> some View { modifier(MarcoWidget(ruta: ruta)) }
}

/// Un círculo que se marca con un toque en el propio widget (iOS 17: el sistema lo cambia al instante y, mientras
/// corre el intent, lo atenúa con invalidatableContent).
struct CasillaStyle: ToggleStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .widgetAccentable()
                .invalidatableContent()
            configuration.label
        }
    }
}

/// Mensaje cuando no hay claves o no hay datos.
struct AvisoWidget: View {
    @Environment(\.widgetFamily) private var familia
    @Environment(\.widgetRenderingMode) private var modo
    let titulo: String
    let detalle: String

    var body: some View {
        let t = Tinta(modo)
        if familia == .accessoryInline {
            Text(titulo)
        } else if familia == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "exclamationmark.circle").font(.system(size: 20, weight: .semibold))
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.system(size: 14, weight: .bold)).foregroundStyle(t.texto)
                Text(detalle).font(.system(size: 11)).foregroundStyle(t.suave).lineLimit(3)
            }
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

/// Una línea de leyenda: punto del color del gráfico y qué es.
struct PuntoLeyenda: View {
    let color: Color
    let texto: String
    var tam: CGFloat = 10

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7).widgetAccentable()
            Text(texto).font(.system(size: tam)).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

/// Cabecera de los widgets de lista: icono, título y un número.
struct CabeceraWidget: View {
    @Environment(\.widgetRenderingMode) private var modo
    let titulo: String
    let simbolo: String
    var cuenta: String?
    var color: Color?

    var body: some View {
        let t = Tinta(modo)
        HStack(spacing: 4) {
            Image(systemName: simbolo).widgetAccentable()
            Text(titulo)
            Spacer(minLength: 2)
            if let cuenta { Text(cuenta).monospacedDigit() }
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(color ?? t.suave)
        .lineLimit(1)
    }
}

/// El lunes de la semana de `dia` ("yyyy-MM-dd"); sirve para las cabeceras L M X J V S D.
enum DiasSemana {
    static let iniciales = ["L", "M", "X", "J", "V", "S", "D"]

    static func fecha(_ dia: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: dia)
    }

    /// Lunes a domingo de la semana en curso, como "yyyy-MM-dd".
    static func semana(de dia: String) -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        guard let d = fecha(dia), let lunes = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: lunes) }.map(Fecha.dia)
    }

    /// «Hoy», «Mañana» o «jue 13».
    static func etiqueta(_ dia: String, hoy: String) -> String {
        guard let d = fecha(dia), let h = fecha(hoy) else { return dia }
        let n = Calendar(identifier: .gregorian).dateComponents([.day], from: h, to: d).day ?? 0
        if n == 0 { return "Hoy" }
        if n == 1 { return "Mañana" }
        return FichaDato.diaCorto(dia)
    }
}
