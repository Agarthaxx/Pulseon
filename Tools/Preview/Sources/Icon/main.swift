import AppKit
import PulseonUI
import SwiftUI

// Fabrique l'iconset de Pulseon à partir de `PulseonAppIcon`, et une planche
// de contrôle pour la regarder.
//
// **Rendre chaque taille séparément, jamais réduire un 1024.** Un trait de
// 6 % du côté fait 62 points en 1024 et 1 point en 16 : la version réduite
// devient une bouillie grise, alors que la même vue redessinée à 16 reste un
// anneau. C'est tout l'intérêt d'une marque vectorielle.

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp"

@MainActor
func png(_ view: some View, width: CGFloat, height: CGFloat, scale: CGFloat = 1, to path: String) {
    let renderer = ImageRenderer(content: view.frame(width: width, height: height))
    renderer.scale = scale

    guard let image = renderer.nsImage,
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let data = bitmap.representation(using: .png, properties: [:])
    else {
        print("échec du rendu : \(path)")
        exit(1)
    }

    do {
        try data.write(to: URL(fileURLWithPath: path))
    } catch {
        print("écriture impossible (\(path)) : \(error.localizedDescription)")
        exit(1)
    }
}

// MARK: - L'iconset

/// Les dix entrées attendues par `iconutil`. Le nom porte la taille en points
/// et le facteur d'échelle ; c'est le pixel qui compte pour le rendu.
let entries: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let iconset = "\(outputDirectory)/Pulseon.iconset"
try? FileManager.default.createDirectory(
    atPath: iconset, withIntermediateDirectories: true
)

MainActor.assumeIsolated {
    for entry in entries {
        png(PulseonAppIcon(), width: entry.pixels, height: entry.pixels, to: "\(iconset)/\(entry.name).png")
    }
    print(iconset)

    // MARK: - La planche de contrôle
    //
    // Deux fonds, parce qu'une icône se voit sur un Dock clair *et* sombre, et
    // les petites tailles, parce que c'est là qu'un dessin s'effondre — le 16
    // est la taille du Finder en liste.

    let sheet = VStack(spacing: 44) {
        PulseonAppIcon().frame(width: 320, height: 320)
        ForEach([Color(white: 0.10), Color(white: 0.92)], id: \.description) { background in
            HStack(alignment: .bottom, spacing: 28) {
                ForEach([128.0, 64.0, 32.0, 16.0], id: \.self) { side in
                    VStack(spacing: 8) {
                        PulseonAppIcon().frame(width: side, height: side)
                        Text("\(Int(side))")
                            .font(.system(size: 10))
                            .foregroundStyle(background == Color(white: 0.10) ? .white : .black)
                    }
                }
            }
            .padding(20)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    .padding(40)
    .background(Color(white: 0.55))

    png(sheet, width: 560, height: 720, scale: 2, to: "\(outputDirectory)/icon-sheet.png")
    print("\(outputDirectory)/icon-sheet.png")
}
