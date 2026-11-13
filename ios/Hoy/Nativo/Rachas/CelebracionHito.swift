import SwiftUI

extension View {
    /// Al marcar un hábito que llega a un hito de racha (7, 14, 30…): llama que crece, el número que sube, el confeti de
    /// completar el día (CelebracionDia, con su háptica «día» y su sonido). Una vez por hábito, hito y día.
    func celebraHitos() -> some View { modifier(VigiaHitos()) }
}

private struct Hito: Equatable {
    var dias: Int
    var nombre: String
    var color: String
    var siguiente: Int?
}

private struct VigiaHitos: ViewModifier {
    @State private var datos = DatosNativos.shared
    @State private var hito: Hito?
    @State private var disparo = 0
    private static let clave = "rachas.hitosCelebrados"

    func body(content: Content) -> some View {
        content
            .overlay { CelebracionDia(disparo: disparo).ignoresSafeArea() }
            .overlay {
                if let hito {
                    TarjetaHito(hito: hito) { withAnimation(Tema.Muelle.pantalla) { self.hito = nil } }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                        .zIndex(2)
                }
            }
            .onChange(of: datos.hoy?.habitos ?? []) { viejos, nuevos in
                guard datos.hoy?.hoy == Fecha.hoy() else { return }
                let hitos = DatosRachas.shared.hitos
                for h in nuevos where h.hecho && hitos.contains(h.racha) {
                    guard let antes = viejos.first(where: { $0.id == h.id }), !antes.hecho else { continue }
                    let marca = "\(Fecha.hoy()):\(h.id):\(h.racha)"
                    var hechos = Almacen.defaults.stringArray(forKey: Self.clave) ?? []
                    guard !hechos.contains(marca) else { continue }
                    hechos = Array((hechos + [marca]).suffix(40))
                    Almacen.defaults.set(hechos, forKey: Self.clave)
                    disparo += 1
                    withAnimation(Tema.Muelle.gota) {
                        hito = Hito(dias: h.racha, nombre: h.n, color: h.c, siguiente: hitos.first { $0 > h.racha })
                    }
                    let este = hito
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3.2))
                        if hito == este { withAnimation(Tema.Muelle.pantalla) { hito = nil } }
                    }
                    break
                }
            }
    }
}

/// La tarjeta del hito: la llama crece desde nada y el número sube del día anterior al del hito.
private struct TarjetaHito: View {
    let hito: Hito
    let cierra: () -> Void
    @Environment(\.accessibilityReduceMotion) private var quieto
    @State private var crecida = false
    @State private var numero = 0

    var body: some View {
        VStack(spacing: Tema.Espacio.s) {
            ZStack {
                Image(systemName: "flame.fill")
                    .font(.system(size: 92, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Tema.aviso, Color(hex: hito.color)], startPoint: .bottom, endPoint: .top))
                    .scaleEffect(crecida ? 1 : 0.2, anchor: .bottom)
                    .symbolEffect(.bounce, value: crecida)
                Text("\(numero)")
                    .font(Tema.fuente(.gigante))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(numero)))
                    .offset(y: 16)
                    .shadow(radius: 4)
            }
            .frame(height: 130)
            Text("¡\(DatosRachas.dias(hito.dias)) de \(hito.nombre)!")
                .font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                .multilineTextAlignment(.center)
            if let s = hito.siguiente {
                Text("Siguiente hito: \(s) días").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
        }
        .padding(Tema.Espacio.xl)
        .frame(maxWidth: 300)
        .background(Tema.carta, in: RoundedRectangle(cornerRadius: Tema.Radio.carta, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
        .onTapGesture(perform: cierra)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nuevo hito: \(DatosRachas.dias(hito.dias)) de \(hito.nombre)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Cerrar", cierra)
        .onAppear {
            numero = quieto ? hito.dias : max(0, hito.dias - 1)
            if quieto {
                crecida = true
                return
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.55)) { crecida = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.45))
                withAnimation(Tema.Muelle.toque) { numero = hito.dias }
            }
        }
    }
}
