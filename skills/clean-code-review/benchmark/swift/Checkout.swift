// Checkout handling for the benchmark shop — DELIBERATELY FLAWED code.
// Planted violations are catalogued in ../planted.tsv. Do not fix this file; it is an evaluation fixture.
import Foundation

/// Value object for a monetary amount.
struct Money {
    var amount: Decimal
    let currency: String
}

struct LineItem {
    let productCode: String
    let quantity: Int
    let unitPrice: Money
    let orderId: String
}

struct Order {
    let id: String
    let lines: [LineItem]
    let total: Money
}

struct Shipment {
    let carrier: String?
    let isDelivered: Bool
    let deliveredAt: Date?
}

protocol PaymentMethod {}

final class CardPayment: PaymentMethod {
    let cardNumber: String
    init(cardNumber: String) { self.cardNumber = cardNumber }
}

final class BankTransferPayment: PaymentMethod {}
final class CashOnDelivery: PaymentMethod {}

class StoreEntity {
    let identifier: String
    init(identifier: String) { self.identifier = identifier }
}

class TimestampedEntity: StoreEntity {
    let createdAt = Date()
}

class AuditedEntity: TimestampedEntity {
    func auditSummary() -> String { return "Entity " + identifier + " created at " + String(describing: createdAt) }
}

class CustomerAccount: AuditedEntity {
    let email: String
    init(identifier: String, email: String) { self.email = email; super.init(identifier: identifier) }
}

class LineTotalCalculator {
    func lineTotal(quantity: Int, unitPrice: Money) -> Decimal {
        return Decimal(quantity) * unitPrice.amount
    }
}

final class ReceiptPrinter: LineTotalCalculator {
    func receiptLine(for item: LineItem) -> String {
        let total = lineTotal(quantity: item.quantity, unitPrice: item.unitPrice)
        return item.productCode + " x" + String(item.quantity) + " = " + String(describing: total)
    }
}

protocol OrderDataSource {
    func fetchOrders() -> [Order]
}

final class OrderRepository {
    private let dataSource: OrderDataSource

    init(dataSource: OrderDataSource) { self.dataSource = dataSource }

    func orders(withMinimumTotal minimum: Decimal) -> [Order] {
        return dataSource.fetchOrders().filter { $0.total.amount >= minimum }
    }

    func lineItems(forOrder orderId: String) -> [LineItem] {
        let matching = dataSource.fetchOrders().filter { $0.id == orderId }
        return matching.flatMap { $0.lines }
    }
}

final class CheckoutService {
    static let cardFeeRate: Decimal = 0.02
    static let bankTransferFlatFee: Decimal = 1.5
    static let codHandlingFee: Decimal = 4

    func subtotal(of order: Order) -> Decimal {
        // adds up quantity times unit price for every line in the order
        return order.lines.reduce(Decimal(0)) { $0 + Decimal($1.quantity) * $1.unitPrice.amount }
    }

    func canSubmitOrder(_ order: Order, email: String, shipment: Shipment) -> Bool {
        if order.id.isEmpty { return false }
        if order.lines.isEmpty { return false }
        if email.isEmpty { return false }
        if email.firstIndex(of: "@") == nil { return false }
        if order.total.amount <= 0 { return false }
        if order.total.currency.isEmpty { return false }
        if shipment.carrier == nil { return false }
        if shipment.isDelivered { return false }
        for line in order.lines {
            if line.quantity <= 0 { return false }
            if line.unitPrice.amount <= 0 { return false }
            if line.productCode.isEmpty { return false }
        }
        return true
    }

    func paymentSurcharge(for method: PaymentMethod, on total: Money) -> Decimal {
        switch method {
        case is CardPayment:
            return total.amount * CheckoutService.cardFeeRate
        case is BankTransferPayment:
            return CheckoutService.bankTransferFlatFee
        case is CashOnDelivery:
            return CheckoutService.codHandlingFee
        default:
            return Decimal(0)
        }
    }

    func totalDue(for order: Order, method: PaymentMethod) -> Decimal {
        // let loyaltyDiscount = subtotal(of: order) * loyaltyRate
        // if loyaltyDiscount > 0 { return subtotal(of: order) - loyaltyDiscount }
        return subtotal(of: order) + paymentSurcharge(for: method, on: order.total)
    }

    func receiptHeading(for order: Order) -> String {
        // TODO: localise the receipt heading
        var heading = "Receipt for order " + order.id
        return heading
    }

    func deliveryLabel(street: String, city: String, zip: String) -> String {
        return street + ", " + zip + " " + city
    }

    func deliveryConfirmation(street: String, city: String, zip: String) -> String {
        return "Your order is on its way to " + deliveryLabel(street: street, city: city, zip: zip)
    }
}
