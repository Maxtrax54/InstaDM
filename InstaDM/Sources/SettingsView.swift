//
//  SettingsView.swift
//  InstaDM
//
//  Ajustes: modo de la app y cerrar sesión / borrar datos.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var modelo: NavegadorModelo
    @Environment(\.dismiss) private var cerrar
    @State private var confirmarBorrado = false

    /// El toggle prende/apaga el modo "Mensajes + Inicio".
    private var modoInicio: Binding<Bool> {
        Binding(
            get: { modelo.modo == .mensajesEInicio },
            set: { modelo.modo = $0 ? .mensajesEInicio : .soloMensajes }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Mensajes + Inicio", isOn: modoInicio)
                } header: {
                    Text("Modo")
                } footer: {
                    Text(modelo.modo == .soloMensajes
                         ? "Solo mensajes: bandeja de entrada, chats y los reels que te mandan. Todo lo demás se bloquea."
                         : "Mensajes + Inicio: suma el feed (sin reels, best-effort), perfiles y posts. Reels y Explorar siguen bloqueados.")
                }

                Section {
                    Button("Cerrar sesión / borrar datos", role: .destructive) {
                        confirmarBorrado = true
                    }
                } footer: {
                    Text("Borra cookies, caché y todo lo que Instagram guardó en la app.")
                }

                Section("Acerca de") {
                    LabeledContent("Versión", value: version)
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { cerrar() }
                }
            }
            .confirmationDialog("¿Cerrar sesión y borrar todos los datos?",
                                isPresented: $confirmarBorrado,
                                titleVisibility: .visible) {
                Button("Borrar todo", role: .destructive) {
                    modelo.borrarDatos()
                    cerrar()
                }
                Button("Cancelar", role: .cancel) {}
            }
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
