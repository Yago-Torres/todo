import ActivityKit
import Foundation

// Compila en la app y en el widget. Una Live Activity genérica para todo lo que no es el entreno serie a serie:
// el descanso suelto, el pase del freno de apps, la subida de un intento de escalada y «Día en la isla».
// Las cuentas atrás las pinta el sistema solo (Text(timerInterval:)): la app no tiene que despertarse.

struct AvisoActividad: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var titulo: String
        var detalle: String
        var icono: String          // SF Symbol
        var inicio: Date?          // cuenta atrás: de inicio a fin
        var fin: Date?
        var progreso: Double?      // 0…1 (la subida)
        var listo: Bool = false
        var anillos: [Double] = [] // «Día en la isla»: hábitos, pasos, sueño (0…1)
    }

    /// descanso | freno | subida | dia
    var tipo: String
}

extension AvisoActividad.ContentState {
    /// Caduca al acabar la cuenta atrás: el widget lo ve (isStale) y deja de enseñar «0:00».
    func contenido(caduca: Date? = nil) -> ActivityContent<Self> {
        ActivityContent(state: self, staleDate: caduca ?? fin)
    }
}
