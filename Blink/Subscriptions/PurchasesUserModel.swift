//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2019 Blink Mobile Shell Project
//
// This file is part of Blink.
//
// Blink is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Blink is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Blink. If not, see <http://www.gnu.org/licenses/>.
//
// In addition, Blink is also subject to certain additional terms under
// GNU GPL version 3 section 7.
//
// You should have received a copy of these additional terms immediately
// following the terms and conditions of the GNU General Public License
// which accompanied the Blink Source Code. If not, see
// <http://www.github.com/blinksh/blink>.
//
////////////////////////////////////////////////////////////////////////////////

import Purchases
import Combine
import SwiftUI

extension CompatibilityAccessManager.Entitlement {
  static let unlimitedTimeAccess = Self("shell")
}

class PurchasesUserModel: ObservableObject {
  @Published var unlimitedTimeAccess: EntitlementStatus = .inactive
  
  @Published var plusProduct: SKProduct? = nil
  @Published var classicProduct: SKProduct? = nil
  @Published var purchaseInProgress: Bool = false
  @Published var restoreInProgress: Bool = false
  
  @Published var recieptIsVerified: Bool = false
  @Published var zeroPriceUnlocked: Bool = false
  @Published var dataCopied: Bool = false
  @Published var migrationStatus: MigrationStatus = .validating
  @Published var alertErrorMessage: String = ""
  
  private let _priceFormatter = NumberFormatter()
  
  private init() {
    _priceFormatter.numberStyle = .currency
    refresh()
  }
  
  static let shared = PurchasesUserModel()
  
  func refresh() {
    let manager = CompatibilityAccessManager.shared
    manager.status(of: .unlimitedTimeAccess).assign(to: &$unlimitedTimeAccess)
    
    if self.plusProduct == nil || self.classicProduct == nil {
      self.fetchProducts()
    }
  }
  
  func purchasePlus() {
    _purchase(product: plusProduct)
  }
  
  func purchaseClassic() {
    _purchase(product: classicProduct)
  }
  
  private func _purchase(product: SKProduct?) {
    guard let product = product else {
      return
    }
    withAnimation {
      self.purchaseInProgress = true
    }
    
    
    Purchases.shared.purchaseProduct(product) { (transaction, purchaseInfo, error, cancelled) in
      self.purchaseInProgress = false
      self.refresh()
    }
  }
  
  func restorePurchases() {
    self.restoreInProgress = true
    Purchases.shared.restoreTransactions { info, error in
      self.refresh()
      self.restoreInProgress = false
    }
  }
  
  func formattedPlustPriceWithPeriod() -> String? {
    guard let product = plusProduct else {
      return nil
    }
    
    _priceFormatter.locale = product.priceLocale
    guard let priceStr = _priceFormatter.string(for: product.price) else {
      return nil
    }
    
    guard let period = product.subscriptionPeriod else {
      return priceStr
    }
    
    let n = period.numberOfUnits
    
    if n <= 1 {
      switch period.unit {
      case .day: return "\(priceStr)/day"
      case .week: return "\(priceStr)/week"
      case .month: return "\(priceStr)/month"
      case .year: return "\(priceStr)/year"
      @unknown default:
        return priceStr
      }
    }
    
    switch period.unit {
    case .day: return "\(priceStr) / \(n) days"
    case .week: return "\(priceStr) / \(n) weeks"
    case .month: return "\(priceStr) / \(n) months"
    case .year: return "\(priceStr) / \(n) years"
    @unknown default:
      return priceStr
    }
  }
  
  func fetchProducts() {
    let plusId = SKProduct.productPlusId
    let classicId = SKProduct.productClassicId
    
    Purchases.shared.products([plusId, classicId]) { products in
      for product in products {
        if product.productIdentifier == plusId {
          self.plusProduct = product
        }
        
        if product.productIdentifier == classicId {
          self.classicProduct = product
        }
      }
      
    }
  }
  
  enum MigrationStatus {
    case validating, accepted
    case denied(error: Error)
  }
  
  func startMigration() {
    migrationStatus = .validating
    let url = URL(string: "blinkv14://validatereceipt?originalUserId=\(Purchases.shared.appUserID)")!
    UIApplication.shared.open(url, completionHandler: { success in
      if success {
        self.alertErrorMessage = ""
      } else {
        self.alertErrorMessage = "Please install Blink 14 latest version first."
      }
    })
  }
  
  func continueMigrationWith(migrationToken: Data) {
    let originalUserId = Purchases.shared.appUserID

    do {
      let migrationToken = try JSONDecoder()
        .decode(MigrationToken.self, from: migrationToken)
      try migrationToken.validateReceiptForMigration(attachedTo: originalUserId)
      migrationStatus = .accepted
      purchaseClassic()
    } catch {
      migrationStatus = .denied(error: error)
    }
  }
  
}

@objc public class PurchasesUserModelObjc: NSObject {

  @objc public static func preparePurchasesUserModel() {
    if !FeatureFlags.checkReceipt {
      PurchasesUserModel.shared.refresh()
    }
  }
}


extension SKProduct {
  static let productPlusId = "blink_shell_plus_1y_1999"
  static let productClassicId = "blink_shell_classic_unlimited_0"
}
