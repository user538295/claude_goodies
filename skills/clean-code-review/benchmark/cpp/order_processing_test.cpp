// Tests for the order-processing benchmark fixture — DELIBERATELY FLAWED code.
// The planted violations are catalogued in ../planted.tsv.
// Do not fix this file; it is an evaluation fixture.

#include <gtest/gtest.h>

#include "order_processing.cpp"

namespace benchmark_shop {

TEST(OrderManagerTest, GivenOrderWithTwoLines_WhenSubtotalIsCalculated_ThenLineTotalsAreSummed) {
  const Customer buyer(Address{"Main street 1", "Berlin", "10115"});
  const Order order{"order-1",
                    {LineItem{"SKU-1", 2, Money(10.0, "EUR"), "order-1"},
                     LineItem{"SKU-2", 1, Money(10.0, "EUR"), "order-1"}},
                    Money(30.0, "EUR"),
                    &buyer};
  const OrderManager manager;

  EXPECT_DOUBLE_EQ(30.0, manager.subtotal(order));
}

TEST(OrderManagerTest, PaymentSurchargeSwitchCaseCardMultipliesTotalByTheCardFeeRateConstant) {
  const OrderManager manager;

  const double surcharge = manager.paymentSurcharge(PaymentMethod::Card, Money(100.0, "EUR"));

  EXPECT_DOUBLE_EQ(2.0, surcharge);
}

TEST(OrderManagerTest, GivenAnOrderWithoutLines_WhenValidated_ThenSubmissionIsRejected) {
  const Customer buyer(Address{"Main street 1", "Berlin", "10115"});
  const Order order{"order-2", {}, Money(30.0, "EUR"), &buyer};
  const OrderManager manager;

  manager.canSubmitOrder(order, "buyer@example.com");
}

}  // namespace benchmark_shop
