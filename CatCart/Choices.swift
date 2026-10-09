import Foundation

// Which cat rides and which cart she rides in. Picked on the home screen and
// saved on the phone, so the next launch starts with the same pair.
// See docs/plans/characters-and-carts.md.

enum CatChoice: String, CaseIterable {
    case lilac, bean, ginger, tux, siamese, fluffy

    /// The name on the home screen's pill.
    var title: String {
        switch self {
        case .lilac: return "Lilac"
        case .bean: return "Bean"
        case .ginger: return "Ginger"
        case .tux: return "Tux"
        case .siamese: return "Miso"
        case .fluffy: return "Fluffy"
        }
    }

    /// Her model in CatCart/Models, built by scripts/build_kitten.sh.
    var modelName: String {
        self == .lilac ? "cat_kitten" : "cat_\(rawValue)"
    }
}

enum CartChoice: String, CaseIterable {
    case lacroix, basket, wagon, bed

    var title: String {
        switch self {
        case .lacroix: return "La Croix"
        case .basket: return "Laundry Basket"
        case .wagon: return "Red Wagon"
        case .bed: return "Cat Bed"
        }
    }
}

extension CaseIterable where Self: Equatable, AllCases == [Self] {
    /// The next one in the list, wrapping around. `step` is +1 or -1.
    func cycled(_ step: Int) -> Self {
        let all = Self.allCases
        let i = all.firstIndex(of: self)!
        return all[(i + step + all.count) % all.count]
    }
}

enum Choices {
    private static let catKey = "catChoice"
    private static let cartKey = "cartChoice"

    static var cat: CatChoice {
        get { UserDefaults.standard.string(forKey: catKey).flatMap(CatChoice.init) ?? .lilac }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: catKey) }
    }

    static var cart: CartChoice {
        get { UserDefaults.standard.string(forKey: cartKey).flatMap(CartChoice.init) ?? .lacroix }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: cartKey) }
    }
}
