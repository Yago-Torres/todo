import SwiftUI

/// Lo que hay debajo de todo con las claves puestas: la pantalla nativa de la sección (Hoy/Nativo/Registro.swift) con
/// el fondo del tema y la barra nativa encima. Las pantallas entran y salen con el muelle del tema, sin cargar nada:
/// cada una pinta al momento su copia local (ya en memoria, ver Precarga) y se refresca por detrás.
struct Pestanas: View {
    let claves: Claves
    @ObservedObject private var navegador = Navegador.shared
    @Environment(\.scenePhase) private var fase
    /// Lo que se ha arrastrado de lado: la pantalla sigue al dedo antes de pasar de página.
    @State private var arrastre: CGFloat = 0
    /// La dirección del arrastre, decidida una vez al empezar: de lado (y hacia una sección que existe) o cualquier otra
    /// cosa. Si no es de lado, en todo ese gesto la página no se mueve (antes un scroll en diagonal la desplazaba).
    @State private var eje: Eje?
    private enum Eje { case lado, otro }

    var body: some View {
        let haciaDelante = Self.indice(navegador.pestana) >= Self.indice(navegador.anterior)
        ZStack(alignment: .bottom) {
            ZStack {
                Tema.fondo.ignoresSafeArea()
                FondoTema().ignoresSafeArea()   // el fondo de cada tema (Decoracion/)
                pantalla
                    .id(navegador.pestana)
                    // como pasar páginas: la nueva entra por un lado y la vieja sale por el otro
                    .transition(.push(from: haciaDelante ? .trailing : .leading))
            }
            .offset(x: arrastre)
            // deslizar a los lados: la página sigue al dedo y, pasado un tercio (o rápido), pasa a la de al lado
            .simultaneousGesture(DragGesture(minimumDistance: 24, coordinateSpace: .global)
                .onChanged { g in
                    if eje == nil { eje = puedeArrastrar(g) && hayVecina(g.translation.width) ? .lado : .otro }
                    // solo se mueve si tiene sentido: de lado y hacia una sección que existe (y sin pasarse al volver)
                    guard eje == .lado, hayVecina(g.translation.width) else { arrastre = 0; return }
                    arrastre = g.translation.width * 0.6
                }
                .onEnded { g in
                    let dx = g.translation.width, rapido = abs(g.predictedEndTranslation.width) > 260
                    let decidido = eje
                    eje = nil
                    defer { withAnimation(Tema.Muelle.pantalla) { arrastre = 0 } }
                    guard decidido == .lado, hayVecina(dx), abs(dx) > 80 || rapido else { return }
                    paso(dx < 0 ? 1 : -1)
                })
            VStack(spacing: Tema.Espacio.s) {
                IndicadorCola()   // «N cambios por enviar» (Cola/), solo si hay algo en la cola
                Dock(actual: Navegador.seccion(navegador.pestana)) { navegador.toca($0) }
            }
                .padding(.bottom, 2)
                .ignoresSafeArea(.keyboard)
        }
        .animation(Tema.Muelle.pantalla, value: navegador.pestana)
        // «?hecho=id» de un aviso o del widget: se marca aquí
        .onChange(of: navegador.marcaPendiente, initial: true) { _, id in
            guard let id else { return }
            navegador.marcaPendiente = nil
            Haptica.shared.toca(.marcar)
            Task { await DatosNativos.shared.marca(id, hecho: true) }
        }
        .onChange(of: fase) { _, nueva in
            if nueva == .active {
                Task { await DatosNativos.shared.carga(margen: 60) }
                Uso.apunta(navegador.pestana)
            }
        }
        // el registro de uso del servidor (uso.py): qué secciones abres y cuándo
        .onChange(of: navegador.pestana, initial: true) { _, p in Uso.apunta(p) }
    }

    /// Solo arrastres claramente horizontales; en las listas con filas que se deslizan (completar, borrar…),
    /// solo desde los bordes.
    private func puedeArrastrar(_ g: DragGesture.Value) -> Bool {
        let dx = g.translation.width, dy = g.translation.height
        guard abs(dx) > abs(dy) * 2 else { return false }
        // empezó en algo que se desplaza de lado (las píldoras de Inversiones, sugerencias…): eso se mueve, la sección no
        if ZonasSinDeslizar.shared.contiene(g.startLocation) { return false }
        if Self.conFilasDeslizables.contains(navegador.pestana) {
            let x = g.startLocation.x, ancho = UIScreen.main.bounds.width
            return x < 28 || x > ancho - 28
        }
        return true
    }

    /// ¿Hay sección al lado hacia donde va el dedo? (arrastrar a la izquierda = la siguiente)
    private func hayVecina(_ dx: CGFloat) -> Bool {
        Dock.visibles().indices.contains(Self.indice(navegador.pestana) + (dx < 0 ? 1 : -1))
    }

    private static let conFilasDeslizables: Set<String> = ["/pendientes.html", "/documentos.html", "/gastos.html"]

    private static func indice(_ pestana: String) -> Int {
        Dock.visibles().firstIndex { $0.href == Navegador.seccion(pestana) } ?? 0
    }

    /// A la sección de al lado según el orden de la barra (dir: 1 siguiente, -1 anterior).
    private func paso(_ dir: Int) {
        let lista = Dock.visibles()
        let i = Self.indice(navegador.pestana) + dir
        guard lista.indices.contains(i) else {
            Haptica.shared.toca(.error)
            return
        }
        Haptica.shared.toca(.marcar)
        navegador.toca(lista[i].href)
    }

    private var pantalla: some View { RegistroNativo.vista(navegador.pestana) }
}

/// Lo que se desplaza de lado dentro de una sección (selectores de píldoras, filas de sugerencias…): un arrastre que
/// empieza ahí mueve eso y no cambia de sección. Cada zona apunta su marco en coordenadas de pantalla mientras se ve.
@MainActor
final class ZonasSinDeslizar {
    static let shared = ZonasSinDeslizar()
    private var zonas: [UUID: CGRect] = [:]

    func pon(_ id: UUID, _ marco: CGRect) { zonas[id] = marco }
    func quita(_ id: UUID) { zonas[id] = nil }
    func contiene(_ punto: CGPoint) -> Bool { zonas.values.contains { $0.insetBy(dx: 0, dy: -6).contains(punto) } }
}

private struct SinDeslizarSeccion: ViewModifier {
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { g in
                    let marco = g.frame(in: .global)
                    Color.clear
                        .onAppear { ZonasSinDeslizar.shared.pon(id, marco) }
                        .onChange(of: marco) { _, nuevo in ZonasSinDeslizar.shared.pon(id, nuevo) }
                }
            }
            .onDisappear { ZonasSinDeslizar.shared.quita(id) }
    }
}

extension View {
    /// Para un ScrollView horizontal dentro de una sección: arrastrar ahí no pasa a la sección de al lado.
    func sinDeslizarSeccion() -> some View { modifier(SinDeslizarSeccion()) }
}

/// El registro de uso del servidor (uso.py, POST /api/uso): la sección o la vista que abres. Sin esperar ni reintentar:
/// si no hay red, ese apunte se pierde y no pasa nada.
enum Uso {
    static func apunta(_ que: String) {
        Task.detached(priority: .background) {
            _ = try? await API.datos("/api/uso", metodo: "POST", json: ["que": que])
        }
    }
}
