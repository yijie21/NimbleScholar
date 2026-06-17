import SwiftUI
import NimbleScholarCore

/// The bar above the canvas: pick the active map, create / rename / delete maps.
struct MapBar: View {
    @EnvironmentObject var vm: MindmapViewModel
    @State private var showNew = false
    @State private var showRename = false
    @State private var nameDraft = ""

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(vm.maps) { map in
                    Button(map.name.isEmpty ? "Untitled idea" : map.name) {
                        if let id = map.id { vm.selectMap(id) }
                    }
                }
                if vm.maps.isEmpty { Text("No maps yet").foregroundStyle(.secondary) }
            } label: {
                Label(vm.activeMap?.name.isEmpty == false ? vm.activeMap!.name : "Select map",
                      systemImage: "brain")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button { nameDraft = ""; showNew = true } label: { Label("New", systemImage: "plus") }
            Button { nameDraft = vm.activeMap?.name ?? ""; showRename = true } label: {
                Label("Rename", systemImage: "pencil")
            }
            .disabled(vm.activeMapID == nil)
            Button(role: .destructive) { vm.deleteActiveMap() } label: { Label("Delete", systemImage: "trash") }
                .disabled(vm.activeMapID == nil)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .alert("New mindmap", isPresented: $showNew) {
            TextField("Name", text: $nameDraft)
            Button("Create") { vm.createMap(name: nameDraft) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename mindmap", isPresented: $showRename) {
            TextField("Name", text: $nameDraft)
            Button("Save") { vm.renameActiveMap(to: nameDraft) }
            Button("Cancel", role: .cancel) {}
        }
    }
}
