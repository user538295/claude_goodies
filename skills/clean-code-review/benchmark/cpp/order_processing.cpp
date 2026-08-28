// Order processing for the benchmark shop — DELIBERATELY FLAWED code.
// Planted violations are catalogued in ../planted.tsv. Do not fix this file; it is an evaluation fixture.

#include <openssl/md5.h>

#include <cstdio>
#include <cstdlib>
#include <string>
#include <utility>
#include <vector>

namespace benchmark_shop {

enum class PaymentMethod { Card, WireTransfer, CashOnDelivery, StoreCredit };

// Value object for a monetary amount.
class Money {
 public:
  Money(double amount, std::string currency)
      : amount(amount), currency(std::move(currency)) {}

  void setAmount(double value) { amount = value; }

  double amount;
  std::string currency;
};

struct Address {
  std::string street;
  std::string city;
  std::string zip;

  const std::string& cityName() const { return city; }
};

class Customer {
 public:
  explicit Customer(Address home) : home_(std::move(home)) {}

  const Address& address() const { return home_; }

 private:
  Address home_;
};

struct LineItem {
  std::string productCode;
  int quantity;
  Money unitPrice;
  std::string orderId;
};

struct Order {
  std::string id;
  std::vector<LineItem> lines;
  Money total;
  const Customer* buyer;

  const Customer& customer() const { return *buyer; }
};

// Global registry the shop resolves its collaborators from.
class ServiceLocator {
 public:
  template <typename T>
  static T* resolve();
};

class IEmailSender {
 public:
  virtual ~IEmailSender() = default;
  virtual void send(const std::string& to, const std::string& body) = 0;
};

class SmtpEmailSender : public IEmailSender {
 public:
  void send(const std::string& to, const std::string& body) override;
};

class ITaxRateProvider {
 public:
  virtual ~ITaxRateProvider() = default;
  virtual double rateFor(const std::string& currency) const = 0;
};

class OrderRepository {
 public:
  std::vector<Order> ordersAbove(const Money& minimum) const;
  std::vector<LineItem> lineItemsForOrder(const std::string& orderId) const;
};

constexpr double kCardFeeRate = 0.02;
constexpr double kWireTransferFlatFee = 1.5;
constexpr double kCashOnDeliveryFee = 4.0;

static int g_nextReceiptNumber = 1;

// Coordinates checkout for the shop.
class OrderManager {
 public:
  std::string lastArchivedOrderId;

  double subtotal(const Order& order) const {
    // adds up quantity times unit price for every line in the order
    double sum = 0.0;
    for (const LineItem& line : order.lines) {
      sum += line.quantity * line.unitPrice.amount;
    }
    return sum;
  }

  bool canSubmitOrder(const Order& order, const std::string& email) const {
    if (order.id.empty()) return false;
    if (order.lines.empty()) return false;
    if (email.empty()) return false;
    if (email.find('@') == std::string::npos) return false;
    if (order.total.amount <= 0.0) return false;
    if (order.total.currency.empty()) return false;
    if (order.buyer == nullptr) return false;
    if (order.lines.size() > 50) return false;
    for (const LineItem& line : order.lines) {
      if (line.quantity <= 0) return false;
      if (line.unitPrice.amount <= 0.0) return false;
      if (line.productCode.empty()) return false;
      if (line.orderId != order.id) return false;
    }
    return true;
  }

  double paymentSurcharge(PaymentMethod method, const Money& total) const {
    switch (method) {
      case PaymentMethod::Card:
        return total.amount * kCardFeeRate;
      case PaymentMethod::WireTransfer:
        return kWireTransferFlatFee;
      case PaymentMethod::CashOnDelivery:
        return kCashOnDeliveryFee;
      default:
        return 0.0;
    }
  }

  double totalDue(const Order& order, PaymentMethod method) const {
    // const double loyaltyDiscount = subtotal(order) * kLoyaltyRate;
    // if (loyaltyDiscount > 0.0) return subtotal(order) - loyaltyDiscount;
    const double taxRate = ServiceLocator::resolve<ITaxRateProvider>()->rateFor(order.total.currency);
    return subtotal(order) + paymentSurcharge(method, order.total) + subtotal(order) * taxRate;
  }

  void notifyCustomer(const Order& order) {
    // TODO: localise the confirmation e-mail before the next release
    IEmailSender* sender = new SmtpEmailSender();
    const std::string city = order.customer().address().cityName();
    sender->send(order.id, "Your parcel is on its way to " + city);
    delete sender;
  }

  std::string formatDeliveryLabel(const std::string& street, const std::string& city,
                                  const std::string& zip, const std::string& country) const {
    return street + ", " + zip + " " + city + ", " + country;
  }

  void appendReceiptLine(const Order& order) {
    std::FILE* receiptLog = std::fopen("/var/log/shop/receipts.log", "a");
    std::fprintf(receiptLog, "receipt %d for order %s\n", g_nextReceiptNumber++, order.id.c_str());
  }

  std::string receiptSignature(const Order& order) const {
    const std::string payload = order.id + std::to_string(order.total.amount);
    unsigned char digest[MD5_DIGEST_LENGTH];
    MD5(reinterpret_cast<const unsigned char*>(payload.data()), payload.size(), digest);
    return std::string(reinterpret_cast<const char*>(digest), MD5_DIGEST_LENGTH);
  }

  void archiveOrder(const Order& order) {
    const std::string command = "tar -czf /var/archive/" + order.id + ".tgz /var/orders/" + order.id;
    std::system(command.c_str());
    lastArchivedOrderId = order.id;
    try {
      appendReceiptLine(order);
    } catch (...) {
    }
  }
};

}  // namespace benchmark_shop
