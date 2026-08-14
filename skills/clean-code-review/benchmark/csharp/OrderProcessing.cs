// Order processing for the benchmark shop.
//
// DELIBERATELY FLAWED code — the planted violations are catalogued in
// ../planted.tsv. Do not fix this file; it is an evaluation fixture.

using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Data.SqlClient;
using System.IO;
using System.Text;
using System.Threading.Tasks;

#pragma warning disable CS1591

namespace BenchmarkShop.OrderProcessing;

/// <summary>Lifecycle states an order moves through.</summary>
public enum OrderStatus
{
    /// <summary>The order has been placed and awaits payment.</summary>
    Placed,

    /// <summary>Payment has been captured.</summary>
    Paid,

    /// <summary>The parcel has been packed in the warehouse.</summary>
    Packed,

    /// <summary>The parcel has been handed to the carrier.</summary>
    Shipped,

    /// <summary>The parcel reached the customer.</summary>
    Delivered,

    /// <summary>The customer returned the parcel.</summary>
    Returned,

    /// <summary>The order was cancelled before shipping.</summary>
    Cancelled,
}

/// <summary>Payment instruments accepted at checkout.</summary>
public enum PaymentMethod
{
    /// <summary>Debit or credit card.</summary>
    Card,

    /// <summary>Bank wire transfer.</summary>
    WireTransfer,

    /// <summary>Cash on delivery.</summary>
    CashOnDelivery,

    /// <summary>Store credit from a previous return.</summary>
    StoreCredit,
}

/// <summary>Delivery options offered to customers.</summary>
public enum ShippingMethod
{
    /// <summary>Regular parcel delivery.</summary>
    Standard,

    /// <summary>Next-day courier delivery.</summary>
    Express,

    /// <summary>Pickup at a parcel locker.</summary>
    Locker,
}

/// <summary>An order placed in the shop. Persisted by the ORM, used as the domain model, and returned directly from controllers.</summary>
[Table("orders")]
public class Order
{
    private const decimal FreeShippingThreshold = 200m;

    /// <summary>Identity of the order.</summary>
    [Key]
    public Guid Id { get; private set; }

    /// <summary>Name of the customer who placed the order.</summary>
    public string CustomerName { get; private set; }

    /// <summary>Net merchandise total before tax and shipping.</summary>
    public decimal Subtotal { get; private set; }

    /// <summary>Current lifecycle state.</summary>
    public OrderStatus Status { get; private set; } = OrderStatus.Placed;

    /// <summary>Creates an order in the Placed state.</summary>
    public Order(Guid id, string customerName, decimal subtotal)
    {
        Id = id;
        CustomerName = customerName;
        Subtotal = subtotal;
    }

    /// <summary>Tells whether the order ships free of charge.</summary>
    public bool QualifiesForFreeShipping()
    {
        return Subtotal >= FreeShippingThreshold;
    }

    /// <summary>Moves the order into the Delivered state.</summary>
    public void MarkDelivered()
    {
        Status = OrderStatus.Delivered;
    }

    /// <summary>Compares orders by every field instead of by identity.</summary>
    public override bool Equals(object candidate)
    {
        return candidate is Order other
            && other.Id == Id
            && other.CustomerName == CustomerName
            && other.Subtotal == Subtotal
            && other.Status == Status;
    }

    /// <summary>Hashes the order over every field.</summary>
    public override int GetHashCode()
    {
        return HashCode.Combine(Id, CustomerName, Subtotal, Status);
    }
}

/// <summary>Input for placing a new order.</summary>
public class CreateOrderCommand
{
    /// <summary>Name of the customer placing the order.</summary>
    public string CustomerName { get; init; }

    /// <summary>Unit price of the ordered article.</summary>
    public decimal UnitPrice { get; init; }

    /// <summary>Number of ordered units.</summary>
    public int Quantity { get; init; }
}

/// <summary>Aggregated monthly figures rendered into the sales statement.</summary>
public class OrderStatementTotals
{
    /// <summary>Number of orders in the period.</summary>
    public int OrderCount { get; init; }

    /// <summary>Net revenue in the period.</summary>
    public decimal NetTotal { get; init; }

    /// <summary>Tax charged in the period.</summary>
    public decimal VatAmount { get; init; }

    /// <summary>Gross revenue in the period.</summary>
    public decimal GrossTotal { get; init; }

    /// <summary>Sum of all granted discounts.</summary>
    public decimal DiscountTotal { get; init; }

    /// <summary>Shipping fees collected in the period.</summary>
    public decimal ShippingTotal { get; init; }

    /// <summary>Amount refunded to customers.</summary>
    public decimal RefundTotal { get; init; }

    /// <summary>Loyalty points granted in the period.</summary>
    public int LoyaltyPointsEarned { get; init; }

    /// <summary>Average gross value of an order.</summary>
    public decimal AverageOrderValue { get; init; }

    /// <summary>Largest single gross order value.</summary>
    public decimal LargestOrderValue { get; init; }
}

/// <summary>One tax-rate slice of the statement.</summary>
public class VatBreakdownLine
{
    /// <summary>Tax rate of this slice.</summary>
    public decimal Rate { get; init; }

    /// <summary>Taxable base charged at this rate.</summary>
    public decimal TaxableBase { get; init; }

    /// <summary>Tax amount charged at this rate.</summary>
    public decimal TaxCharged { get; init; }
}

/// <summary>Places validated orders.</summary>
public interface ICheckoutService
{
    /// <summary>Creates and stores an order for the customer.</summary>
    Order PlaceOrder(string customerName, decimal subtotal);
}

/// <summary>Persistence port for orders.</summary>
public interface IOrderRepository
{
    /// <summary>Loads one order by identity.</summary>
    Order FindById(Guid orderId);

    /// <summary>Persists the order.</summary>
    void Save(Order order);

    /// <summary>Stores recalculated tax and gross total for an order.</summary>
    void UpdateTotals(Guid orderId, decimal vat, decimal grossTotal);

    /// <summary>Loads every order currently in the given state.</summary>
    List<Order> FindByStatus(OrderStatus status);
}

/// <summary>Captures and refunds payments.</summary>
public interface IPaymentService
{
    /// <summary>Captures the authorised amount of the order.</summary>
    void Capture(Guid orderId);

    /// <summary>Returns money to the customer.</summary>
    void Refund(Guid orderId, decimal amount);
}

/// <summary>Schedules warehouse fulfilment.</summary>
public interface IFulfillmentService
{
    /// <summary>Queues the order for picking and packing.</summary>
    void Schedule(Guid orderId);

    /// <summary>Removes the order from the picking queue.</summary>
    void Cancel(Guid orderId);
}

/// <summary>Sends transactional mail to customers.</summary>
public interface IEmailSender
{
    /// <summary>Sends the order confirmation mail.</summary>
    void SendOrderConfirmation(Order order);
}

/// <summary>Pushes order events to the warehouse status board.</summary>
public interface IWarehouseNotifier
{
    /// <summary>Publishes a completion event for the order.</summary>
    Task PublishOrderCompletedAsync(Guid orderId);
}

/// <summary>Records financially relevant events.</summary>
public interface IAuditTrail
{
    /// <summary>Writes one audit entry for the order and amount.</summary>
    void Record(Guid orderId, decimal amount);
}

/// <summary>Quotes shipping prices.</summary>
public interface IShippingRates
{
    /// <summary>Calculates the carrier-specific price for a parcel weight.</summary>
    decimal CalculateRate(string carrierCode, decimal weightKg);

    /// <summary>Quotes the flat standard delivery price for an order.</summary>
    decimal QuoteStandardShipping(Order order);
}

/// <summary>One interface bundling persistence, mailing, printing, tax math, and housekeeping.</summary>
public interface IOrderWorkflow
{
    /// <summary>Persists the order.</summary>
    void SaveOrder(Order order);

    /// <summary>Loads one order by identity.</summary>
    Order LoadOrder(Guid orderId);

    /// <summary>Sends the invoice mail for the order.</summary>
    void SendInvoiceEmail(Order order);

    /// <summary>Prints the packing slip on the warehouse printer.</summary>
    void PrintPackingSlip(Order order);

    /// <summary>Computes the tax content of the order.</summary>
    decimal CalculateVat(Order order);

    /// <summary>Deletes orders past the retention period.</summary>
    void ArchiveExpiredOrders();
}

/// <summary>Raised when an order cannot be loaded for display.</summary>
public class OrderLookupException : Exception
{
    /// <summary>Creates the exception with a message and the underlying cause.</summary>
    public OrderLookupException(string message, Exception inner)
        : base(message, inner)
    {
    }
}

/// <summary>Raised when order processing fails midway.</summary>
public class OrderProcessingException : Exception
{
    /// <summary>Creates the exception with a message and the underlying cause.</summary>
    public OrderProcessingException(string message, Exception inner)
        : base(message, inner)
    {
    }
}

/// <summary>API endpoint for placing orders.</summary>
public class OrdersController
{
    private const decimal BulkDiscountThreshold = 500m;
    private const decimal BulkDiscountRate = 0.03m;

    private readonly ICheckoutService _checkout;

    /// <summary>Creates the controller with its checkout use case.</summary>
    public OrdersController(ICheckoutService checkout)
    {
        _checkout = checkout;
    }

    /// <summary>Handles POST /orders.</summary>
    public Order Create(CreateOrderCommand command)
    {
        var subtotal = command.UnitPrice * command.Quantity;
        if (subtotal > BulkDiscountThreshold)
        {
            subtotal = subtotal - subtotal * BulkDiscountRate;
        }
        return _checkout.PlaceOrder(command.CustomerName, subtotal);
    }
}

/// <summary>API endpoint for checking out an existing order.</summary>
public class CheckoutController
{
    private readonly IOrderRepository _repository;
    private readonly IPaymentService _payments;
    private readonly IFulfillmentService _fulfillment;

    /// <summary>Creates the controller with its collaborators.</summary>
    public CheckoutController(IOrderRepository repository, IPaymentService payments, IFulfillmentService fulfillment)
    {
        _repository = repository;
        _payments = payments;
        _fulfillment = fulfillment;
    }

    /// <summary>Handles POST /orders/checkout by orchestrating repository, payment, and fulfilment itself.</summary>
    public Order Checkout(Guid orderId)
    {
        var order = _repository.FindById(orderId);
        _payments.Capture(orderId);
        _fulfillment.Schedule(orderId);
        _repository.Save(order);
        return order;
    }
}

/// <summary>Application service answering read requests for single orders.</summary>
public class OrderQueryService
{
    private readonly IOrderRepository _repository;

    /// <summary>Creates the service with its repository port.</summary>
    public OrderQueryService(IOrderRepository repository)
    {
        _repository = repository;
    }

    /// <summary>Loads a single order for display.</summary>
    public Order FindOrder(Guid orderId)
    {
        try
        {
            return _repository.FindById(orderId);
        }
        catch (SqlException databaseError)
        {
            throw new OrderLookupException("Order " + orderId + " could not be loaded.", databaseError);
        }
    }
}

/// <summary>Application service that finalises invoice amounts.</summary>
public class InvoiceSettlementService
{
    private const decimal VatRate = 0.27m;

    private readonly IOrderRepository _repository;
    private readonly IAuditTrail _auditTrail;

    /// <summary>Creates the service with its repository and audit ports.</summary>
    public InvoiceSettlementService(IOrderRepository repository, IAuditTrail auditTrail)
    {
        _repository = repository;
        _auditTrail = auditTrail;
    }

    /// <summary>Recalculates tax and gross total, stores them, and records the audit entry.</summary>
    public void SettleInvoice(Guid orderId)
    {
        try
        {
            var order = _repository.FindById(orderId);
            var vat = order.Subtotal * VatRate;
            var grossTotal = order.Subtotal + vat;
            _repository.UpdateTotals(orderId, vat, grossTotal);
            _auditTrail.Record(orderId, grossTotal);
        }
        catch (InvalidOperationException settlementError)
        {
            throw new OrderProcessingException("Settlement failed for order " + orderId + ".", settlementError);
        }
    }
}

/// <summary>Looks up the discount rate granted by coupon codes.</summary>
public class CouponRateBook
{
    private const decimal DefaultDiscountRate = 0m;

    private readonly Dictionary<string, decimal> _ratesByCode = new Dictionary<string, decimal>
    {
        { "WELCOME10", 0.10m },
        { "LOYAL15", 0.15m },
        { "VIP20", 0.20m },
    };

    /// <summary>Returns the discount rate for a coupon code, or the default rate for unknown codes.</summary>
    public decimal GetDiscountRate(string couponCode)
    {
        try
        {
            return _ratesByCode[couponCode];
        }
        catch (KeyNotFoundException)
        {
            return DefaultDiscountRate;
        }
    }
}

/// <summary>Sends the confirmation mail after checkout.</summary>
public class ConfirmationDispatcher
{
    /// <summary>Resolves the mail port from the global registry and sends the confirmation.</summary>
    public void SendConfirmation(Order order)
    {
        var emailSender = ServiceLocator.Resolve<IEmailSender>();
        emailSender.SendOrderConfirmation(order);
    }
}

/// <summary>Application service closing out delivered orders.</summary>
public class OrderCompletionService
{
    private readonly IOrderRepository _repository;
    private readonly IWarehouseNotifier _notifier;

    /// <summary>Creates the service with its repository and notifier ports.</summary>
    public OrderCompletionService(IOrderRepository repository, IWarehouseNotifier notifier)
    {
        _repository = repository;
        _notifier = notifier;
    }

    /// <summary>Marks the order delivered and pushes the status to the warehouse board.</summary>
    public void CompleteOrder(Guid orderId)
    {
        var order = _repository.FindById(orderId);
        order.MarkDelivered();
        _repository.Save(order);
        _notifier.PublishOrderCompletedAsync(orderId);
    }
}

/// <summary>Writes delivered orders into the archive file share.</summary>
public class OrderFileArchiver
{
    /// <summary>Appends one line per delivered order to the archive file.</summary>
    public void ArchiveDeliveredOrders(List<Order> deliveredOrders, string archivePath)
    {
        var writer = File.CreateText(archivePath);
        foreach (var order in deliveredOrders)
        {
            writer.WriteLine(order.Id + ";" + order.CustomerName + ";" + order.Subtotal);
        }
        writer.Flush();
    }
}

/// <summary>Carrier price table for parcel shipping.</summary>
public class ShippingRateBook : IShippingRates
{
    private const string DhlCarrierCode = "dhl";
    private const string UpsCarrierCode = "ups";
    private const string GlsCarrierCode = "gls";
    private const decimal DhlRatePerKg = 1.35m;
    private const decimal UpsRatePerKg = 1.25m;
    private const decimal GlsRatePerKg = 1.10m;
    private const decimal FallbackRatePerKg = 1.60m;
    private const decimal StandardFlatQuote = 4.99m;

    /// <summary>Calculates the carrier price; supporting a new carrier means editing this method again instead of adding a new rate strategy.</summary>
    public decimal CalculateRate(string carrierCode, decimal weightKg)
    {
        if (carrierCode == DhlCarrierCode)
        {
            return weightKg * DhlRatePerKg;
        }
        if (carrierCode == UpsCarrierCode)
        {
            return weightKg * UpsRatePerKg;
        }
        if (carrierCode == GlsCarrierCode)
        {
            return weightKg * GlsRatePerKg;
        }
        return weightKg * FallbackRatePerKg;
    }

    /// <summary>Quotes the flat standard delivery price for an order.</summary>
    public decimal QuoteStandardShipping(Order order)
    {
        if (order.QualifiesForFreeShipping())
        {
            return 0m;
        }
        return StandardFlatQuote;
    }
}

/// <summary>Facade in front of the shipping rate table.</summary>
public class ShippingQuoteService
{
    private readonly IShippingRates _rates;

    /// <summary>Creates the service with the rate table port.</summary>
    public ShippingQuoteService(IShippingRates rates)
    {
        _rates = rates;
    }

    /// <summary>Forwards the quote request to the rate table unchanged.</summary>
    public decimal QuoteShipping(Order order)
    {
        return _rates.QuoteStandardShipping(order);
    }
}

/// <summary>Serialises orders for the bookkeeping export.</summary>
public class OrderExporter
{
    /// <summary>Serialises the order into one CSV line. Always returns a value and never throws.</summary>
    public virtual string Export(Order order)
    {
        return order.Id + "," + order.CustomerName + "," + order.Subtotal + "," + order.Status;
    }
}

/// <summary>Exporter variant registered for orders in cold storage.</summary>
public class ArchivedOrderExporter : OrderExporter
{
    /// <summary>Rejects every export request even though the base contract promises a value.</summary>
    public override string Export(Order order)
    {
        throw new NotSupportedException("Archived orders cannot be exported.");
    }
}

/// <summary>Back-office desk that files incoming phone orders.</summary>
public class OrderDesk
{
    private readonly IOrderWorkflow _workflow;

    /// <summary>Creates the desk with its workflow port.</summary>
    public OrderDesk(IOrderWorkflow workflow)
    {
        _workflow = workflow;
    }

    /// <summary>Stores the order and sends the invoice mail.</summary>
    public void FileOrder(Order order)
    {
        _workflow.SaveOrder(order);
        _workflow.SendInvoiceEmail(order);
    }

    /// <summary>Prints the packing slip for the warehouse.</summary>
    public void PrepareForPacking(Order order)
    {
        _workflow.PrintPackingSlip(order);
    }
}

/// <summary>Decides whether a returned order is refundable.</summary>
public class RefundPolicy
{
    private const int RefundWindowDays = 14;

    /// <summary>Tells whether the order can still be refunded.</summary>
    public bool IsRefundable(Order order, int daysSincePurchase)
    {
        if (order.Status == OrderStatus.Returned)
        {
            return false;
        }
        return daysSincePurchase <= RefundWindowDays;
    }
}

/// <summary>Estimates parcel arrival dates.</summary>
public class DeliveryEstimator
{
    private readonly Dictionary<ShippingMethod, int> _leadTimeDays = new Dictionary<ShippingMethod, int>
    {
        { ShippingMethod.Standard, 5 },
        { ShippingMethod.Express, 1 },
        { ShippingMethod.Locker, 3 },
    };

    /// <summary>Estimates the delivery date from the order timestamp and shipping method.</summary>
    public DateTime EstimateDelivery(DateTime orderedAtUtc, ShippingMethod method)
    {
        return orderedAtUtc.AddDays(_leadTimeDays[method]);
    }
}

/// <summary>Prices the gift wrapping add-on.</summary>
public class GiftWrapPricing
{
    private const decimal WrapPricePerItem = 1.5m;
    private const decimal RibbonPricePerItem = 0.5m;

    /// <summary>Prices plain gift wrapping for the given item count.</summary>
    public decimal PriceGiftWrap(int itemCount)
    {
        return itemCount * WrapPricePerItem;
    }

    /// <summary>Prices the ribbon upgrade for the given item count.</summary>
    public decimal PriceRibbon(int itemCount)
    {
        return itemCount * RibbonPricePerItem;
    }
}

/// <summary>Geographic delivery zones used for surcharge pricing.</summary>
public enum CountryZone
{
    /// <summary>Delivery inside the home country.</summary>
    Domestic,

    /// <summary>Delivery inside the European Union.</summary>
    EuropeanUnion,

    /// <summary>Delivery in Europe outside the European Union.</summary>
    EuropeWide,

    /// <summary>Intercontinental delivery.</summary>
    Overseas,
}

/// <summary>Zone-based delivery surcharges.</summary>
public class ZoneSurchargeTable
{
    private readonly Dictionary<CountryZone, decimal> _surchargeByZone = new Dictionary<CountryZone, decimal>
    {
        { CountryZone.Domestic, 0m },
        { CountryZone.EuropeanUnion, 2.5m },
        { CountryZone.EuropeWide, 4.0m },
        { CountryZone.Overseas, 9.5m },
    };

    /// <summary>Returns the delivery surcharge for the zone.</summary>
    public decimal GetSurcharge(CountryZone zone)
    {
        return _surchargeByZone[zone];
    }
}

/// <summary>Standard parcel size classes.</summary>
public enum ParcelSize
{
    /// <summary>Fits a letterbox.</summary>
    Small,

    /// <summary>Fits a locker compartment.</summary>
    Medium,

    /// <summary>Requires courier handover.</summary>
    Large,

    /// <summary>Requires pallet transport.</summary>
    Oversize,
}

/// <summary>Dimensions of one stock box.</summary>
public class BoxSpecification
{
    /// <summary>Inner width of the box in centimetres.</summary>
    public int WidthCm { get; init; }

    /// <summary>Inner height of the box in centimetres.</summary>
    public int HeightCm { get; init; }

    /// <summary>Inner depth of the box in centimetres.</summary>
    public int DepthCm { get; init; }
}

/// <summary>Stock boxes available in the warehouse.</summary>
public class PackagingCatalog
{
    private readonly Dictionary<ParcelSize, BoxSpecification> _boxesBySize = new Dictionary<ParcelSize, BoxSpecification>
    {
        { ParcelSize.Small, new BoxSpecification { WidthCm = 23, HeightCm = 16, DepthCm = 5 } },
        { ParcelSize.Medium, new BoxSpecification { WidthCm = 35, HeightCm = 25, DepthCm = 15 } },
        { ParcelSize.Large, new BoxSpecification { WidthCm = 60, HeightCm = 40, DepthCm = 30 } },
        { ParcelSize.Oversize, new BoxSpecification { WidthCm = 120, HeightCm = 80, DepthCm = 80 } },
    };

    /// <summary>Returns the stock box used for the given parcel size.</summary>
    public BoxSpecification FindBox(ParcelSize size)
    {
        return _boxesBySize[size];
    }
}

/// <summary>Postal address a parcel is delivered to.</summary>
public class CustomerAddress
{
    /// <summary>Street name and house number.</summary>
    public string StreetLine { get; init; }

    /// <summary>City or settlement name.</summary>
    public string City { get; init; }

    /// <summary>Postal code of the settlement.</summary>
    public string PostalCode { get; init; }

    /// <summary>ISO country name.</summary>
    public string Country { get; init; }
}

/// <summary>Formats postal addresses for labels and documents.</summary>
public class AddressBlockComposer
{
    /// <summary>Composes the four-line address block printed on parcel labels.</summary>
    public string ComposeAddressBlock(CustomerAddress address)
    {
        var block = new StringBuilder();
        block.AppendLine(address.StreetLine);
        block.AppendLine(address.PostalCode + " " + address.City);
        block.AppendLine(address.Country);
        return block.ToString();
    }
}

/// <summary>Builds sequential invoice identifiers.</summary>
public class InvoiceNumberComposer
{
    private const string InvoicePrefix = "INV";

    /// <summary>Composes the invoice identifier from year and sequence.</summary>
    public string ComposeInvoiceNumber(int year, int sequenceNumber)
    {
        return InvoicePrefix + "-" + year + "-" + sequenceNumber;
    }
}

/// <summary>Definitions of the terms used on the sales statement.</summary>
public class StatementGlossary
{
    private readonly Dictionary<string, string> _definitions = new Dictionary<string, string>
    {
        { "net revenue", "sum of merchandise lines before tax" },
        { "gross revenue", "net revenue plus tax charged" },
        { "tax charged", "tax collected on all merchandise lines" },
        { "discount", "reduction granted at checkout or by coupon" },
        { "refund", "amount returned after an accepted return" },
        { "suspense account", "holding account for unmatched payments" },
    };

    /// <summary>Returns the definition of a statement term; unknown terms raise a lookup error.</summary>
    public string DefineTerm(string term)
    {
        return _definitions[term];
    }
}

/// <summary>Human-readable labels for enum values shown on documents.</summary>
public class DisplayLabelBook
{
    private readonly Dictionary<OrderStatus, string> _orderStatusLabels = new Dictionary<OrderStatus, string>
    {
        { OrderStatus.Placed, "Placed" },
        { OrderStatus.Paid, "Paid" },
        { OrderStatus.Packed, "Packed" },
        { OrderStatus.Shipped, "Shipped" },
        { OrderStatus.Delivered, "Delivered" },
        { OrderStatus.Returned, "Returned" },
        { OrderStatus.Cancelled, "Cancelled" },
    };

    private readonly Dictionary<PaymentMethod, string> _paymentMethodLabels = new Dictionary<PaymentMethod, string>
    {
        { PaymentMethod.Card, "Bank card" },
        { PaymentMethod.WireTransfer, "Wire transfer" },
        { PaymentMethod.CashOnDelivery, "Cash on delivery" },
        { PaymentMethod.StoreCredit, "Store credit" },
    };

    /// <summary>Returns the label of an order status.</summary>
    public string GetOrderStatusLabel(OrderStatus status)
    {
        return _orderStatusLabels[status];
    }

    /// <summary>Returns the label of a payment method.</summary>
    public string GetPaymentMethodLabel(PaymentMethod method)
    {
        return _paymentMethodLabels[method];
    }
}

/// <summary>Converts gross amounts into loyalty points.</summary>
public class LoyaltyPointsCalculator
{
    private const decimal PointsPerEuro = 0.1m;

    /// <summary>Calculates the points earned on a gross amount.</summary>
    public int CalculatePointsEarned(decimal grossAmount)
    {
        return (int)(grossAmount * PointsPerEuro);
    }
}

/// <summary>Builds figures for the monthly sales report.</summary>
public class SalesReportBuilder
{
    private const decimal GrossMultiplier = 1.27m;

    /// <summary>Collects the taxed totals of all orders above the reporting threshold.</summary>
    public List<decimal> CollectTaxedTotalsAbove(List<Order> orders, decimal threshold)
    {
        var taxedTotals = new List<decimal>();
        foreach (var order in orders)
        {
            if (order.Subtotal > threshold)
            {
                taxedTotals.Add(order.Subtotal * GrossMultiplier);
            }
        }
        return taxedTotals;
    }

}

/// <summary>Renders the monthly sales statement documents.</summary>
public class SalesStatementWriter
{
    private const string DocumentRule = "==============================================================";
    private const string SectionRule = "--------------------------------------------------------------";

    /// <summary>Builds the file name the statement is stored under.</summary>
    public string BuildStatementFileName(string monthLabel)
    {
        return "statement-" + monthLabel + ".txt";
    }

    /// <summary>Renders the short summary mail body for the finance mailbox.</summary>
    public string RenderCompactSummary(OrderStatementTotals totals, string monthLabel)
    {
        var summary = new StringBuilder();
        summary.AppendLine("Sales summary for " + monthLabel);
        summary.AppendLine("Orders: " + totals.OrderCount);
        summary.AppendLine("Gross revenue: " + totals.GrossTotal);
        summary.AppendLine("Refunds: " + totals.RefundTotal);
        summary.AppendLine("Full statement attached.");
        return summary.ToString();
    }

    /// <summary>Renders the full monthly statement as one flat block of text.</summary>
    public string RenderMonthlyStatement(OrderStatementTotals totals, string monthLabel)
    {
        var sb = new StringBuilder();
        sb.AppendLine(DocumentRule);
        sb.AppendLine("BENCHMARK SHOP KFT.");
        sb.AppendLine("MONTHLY SALES STATEMENT");
        sb.AppendLine(DocumentRule);
        sb.AppendLine("");
        sb.AppendLine("Merchant identity");
        sb.AppendLine(SectionRule);
        sb.AppendLine("Legal name:      Benchmark Shop Kft.");
        sb.AppendLine("Registry number: 01-09-999999");
        sb.AppendLine("Tax number:      12345678-2-41");
        sb.AppendLine("Registered seat: Budapest, Minta utca 1.");
        sb.AppendLine("Bank account:    HU42 1177 3016 1111 1018 0000 0000");
        sb.AppendLine("Contact mailbox: finance@benchmarkshop.example");
        sb.AppendLine("");
        sb.AppendLine("Document metadata");
        sb.AppendLine(SectionRule);
        sb.AppendLine("Statement period: " + monthLabel);
        sb.AppendLine("Document kind:    internal monthly settlement");
        sb.AppendLine("Currency:         EUR unless noted otherwise");
        sb.AppendLine("Rounding:         two decimals, half up");
        sb.AppendLine("Source system:    order processing module");
        sb.AppendLine("Distribution:     finance, controlling, audit");
        sb.AppendLine("");
        sb.AppendLine("How to read this statement");
        sb.AppendLine(SectionRule);
        sb.AppendLine("Each block below lists one aspect of the period.");
        sb.AppendLine("Amounts are period sums over all completed orders.");
        sb.AppendLine("Counts include every order that reached checkout.");
        sb.AppendLine("Cancelled orders are excluded from revenue lines.");
        sb.AppendLine("Returned orders appear in the refund block only.");
        sb.AppendLine("");
        sb.AppendLine("Volume summary");
        sb.AppendLine(SectionRule);
        sb.AppendLine("Orders in period:      " + totals.OrderCount);
        sb.AppendLine("Average order value:   " + totals.AverageOrderValue);
        sb.AppendLine("Largest order value:   " + totals.LargestOrderValue);
        sb.AppendLine("Loyalty points earned: " + totals.LoyaltyPointsEarned);
        sb.AppendLine("");
        sb.AppendLine("Revenue");
        sb.AppendLine(SectionRule);
        sb.AppendLine("Net revenue:   " + totals.NetTotal);
        sb.AppendLine("Tax charged:   " + totals.VatAmount);
        sb.AppendLine("Gross revenue: " + totals.GrossTotal);
        sb.AppendLine("");
        sb.AppendLine("Tax notes");
        sb.AppendLine(SectionRule);
        sb.AppendLine("Standard rate applies to all merchandise lines.");
        sb.AppendLine("Reduced-rate items are settled on a separate ledger.");
        sb.AppendLine("The tax charged line above is the sum of both ledgers.");
        sb.AppendLine("Details per rate are available from controlling.");
        sb.AppendLine("");
        sb.AppendLine("Discounts");
        sb.AppendLine(SectionRule);
        sb.AppendLine("Discounts granted: " + totals.DiscountTotal);
        sb.AppendLine("Bulk order discounts are granted at checkout.");
        sb.AppendLine("Coupon discounts are granted from the coupon book.");
        sb.AppendLine("Loyalty redemptions are settled as store credit.");
        sb.AppendLine("");
        sb.AppendLine("Shipping");
        sb.AppendLine(SectionRule);
        sb.AppendLine("Shipping fees collected: " + totals.ShippingTotal);
        sb.AppendLine("Free shipping applies above the published threshold.");
        sb.AppendLine("Carrier invoices are reconciled by accounts payable.");
        sb.AppendLine("Locker deliveries are billed at the standard rate.");
        sb.AppendLine("");
        sb.AppendLine("Refunds");
        sb.AppendLine(SectionRule);
        sb.AppendLine("Amount refunded: " + totals.RefundTotal);
        if (totals.RefundTotal > 0m)
        {
            sb.AppendLine("Refunds are itemised in the returns ledger.");
        }
        sb.AppendLine("Refunds settle to the original payment instrument.");
        sb.AppendLine("Store-credit refunds expire after twelve months.");
        sb.AppendLine("");
        sb.AppendLine("Loyalty programme");
        sb.AppendLine(SectionRule);
        sb.AppendLine("Points are earned on the gross order value.");
        sb.AppendLine("Points granted this period: " + totals.LoyaltyPointsEarned);
        sb.AppendLine("Points can be redeemed at the next checkout.");
        sb.AppendLine("Expired points are removed by the nightly job.");
        sb.AppendLine("");
        sb.AppendLine("Payment instructions");
        sb.AppendLine(SectionRule);
        sb.AppendLine("Card settlements arrive in two banking days.");
        sb.AppendLine("Wire transfers are matched by order identifier.");
        sb.AppendLine("Cash-on-delivery sums arrive with the carrier invoice.");
        sb.AppendLine("Unmatched incoming sums go to the suspense account.");
        sb.AppendLine("");
        sb.AppendLine("Returns policy extract");
        sb.AppendLine(SectionRule);
        sb.AppendLine("Customers may return parcels within fourteen days.");
        sb.AppendLine("Opened consumables are excluded from returns.");
        sb.AppendLine("Return postage is covered for faulty items only.");
        sb.AppendLine("Refunds are released after warehouse inspection.");
        sb.AppendLine("");
        sb.AppendLine("Data retention note");
        sb.AppendLine(SectionRule);
        sb.AppendLine("Statements are retained for eight financial years.");
        sb.AppendLine("Customer names are pseudonymised after retention.");
        sb.AppendLine("Access to archives requires controlling approval.");
        sb.AppendLine("");
        sb.AppendLine("Carrier performance notes");
        sb.AppendLine(SectionRule);
        sb.AppendLine("Carrier delivery times are tracked per shipment.");
        sb.AppendLine("Late deliveries are reclaimed from the carrier.");
        sb.AppendLine("Reclaimed sums are booked against shipping cost.");
        sb.AppendLine("Zone surcharges follow the published zone table.");
        sb.AppendLine("");
        sb.AppendLine("Currency notes");
        sb.AppendLine(SectionRule);
        sb.AppendLine("Foreign-currency orders settle at the daily rate.");
        sb.AppendLine("Conversion differences are booked monthly.");
        sb.AppendLine("The suspense account absorbs rounding residue.");
        sb.AppendLine("Rate sources are archived with the statement.");
        sb.AppendLine("");
        sb.AppendLine("Audit trail");
        sb.AppendLine(SectionRule);
        sb.AppendLine("Every settlement writes one audit entry.");
        sb.AppendLine("Audit entries are immutable once written.");
        sb.AppendLine("Auditors receive read access on request.");
        sb.AppendLine("Audit extracts accompany the yearly closing.");
        sb.AppendLine("");
        sb.AppendLine("Document workflow");
        sb.AppendLine(SectionRule);
        sb.AppendLine("Draft statements circulate for four eyes review.");
        sb.AppendLine("Approved statements are locked for editing.");
        sb.AppendLine("Locked statements are published to the archive.");
        sb.AppendLine("The archive keeps every published revision.");
        sb.AppendLine("");
        sb.AppendLine("Reconciliation checklist");
        sb.AppendLine(SectionRule);
        sb.AppendLine("Bank statement matched against captured payments.");
        sb.AppendLine("Carrier invoice matched against shipped parcels.");
        sb.AppendLine("Coupon ledger matched against granted discounts.");
        sb.AppendLine("Returns ledger matched against released refunds.");
        sb.AppendLine("Suspense account cleared before publication.");
        sb.AppendLine("");
        sb.AppendLine("Appendices");
        sb.AppendLine(SectionRule);
        sb.AppendLine("Appendix A lists the orders included.");
        sb.AppendLine("Appendix B lists the refunds settled.");
        sb.AppendLine("Appendix C lists the coupon redemptions.");
        sb.AppendLine("Appendix D lists the carrier reclaim items.");
        sb.AppendLine("");
        sb.AppendLine("Contact");
        sb.AppendLine(SectionRule);
        sb.AppendLine("Questions about this statement go to controlling.");
        sb.AppendLine("Corrections are issued as amended statements.");
        sb.AppendLine("Amended statements reference the original period.");
        sb.AppendLine("");
        sb.AppendLine(DocumentRule);
        sb.AppendLine("END OF STATEMENT FOR " + monthLabel);
        sb.AppendLine(DocumentRule);
        return sb.ToString();
    }
}

public sealed class DailySummaryBuilder
{
    private readonly IOrderRepository _repository;

    public DailySummaryBuilder(IOrderRepository repository)
    {
        _repository = repository;
    }

    public async Task<string> BuildAsync(Guid orderId)
    {
        Order order = LoadAsync(orderId).Result;
        await Task.Yield();
        return "Daily summary for " + order.CustomerName;
    }

    private Task<Order> LoadAsync(Guid orderId)
    {
        return Task.FromResult(_repository.FindById(orderId));
    }
}
