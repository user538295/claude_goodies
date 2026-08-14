// Tests for the benchmark shop order processing.
//
// DELIBERATELY FLAWED test code — the planted violations are catalogued in
// ../planted.tsv. Do not fix this file; it is an evaluation fixture.

using System;
using System.Collections.Generic;
using Moq;
using NUnit.Framework;

namespace BenchmarkShop.OrderProcessing;

[TestFixture]
public class OrderProcessingTests
{
    [Test]
    public void should_capture_payment_and_schedule_fulfillment_when_order_is_checked_out()
    {
        var orderId = new Guid("6f9619ff-8b86-d011-b42d-00c04fc964ff");
        var order = new Order(orderId, "Alice Kovacs", 120m);
        var repository = new Mock<IOrderRepository>();
        repository.Setup(r => r.FindById(orderId)).Returns(order);
        repository.Setup(r => r.FindByStatus(OrderStatus.Placed)).Returns(new List<Order> { order });
        repository.Setup(r => r.Save(order));
        repository.Setup(r => r.UpdateTotals(orderId, 0m, 120m));
        var payments = new Mock<IPaymentService>();
        payments.Setup(p => p.Capture(orderId));
        payments.Setup(p => p.Refund(orderId, 0m));
        var fulfillment = new Mock<IFulfillmentService>();
        fulfillment.Setup(f => f.Schedule(orderId));
        fulfillment.Setup(f => f.Cancel(orderId));
        var controller = new CheckoutController(repository.Object, payments.Object, fulfillment.Object);

        var result = controller.Checkout(orderId);

        Assert.AreEqual(orderId, result.Id);
        payments.Verify(p => p.Capture(orderId), Times.Once);
    }

    [Test]
    public void should_return_default_discount_rate_when_coupon_code_is_unknown()
    {
        var rateBook = new CouponRateBook();

        var rate = rateBook.GetDiscountRate("UNKNOWN");

        Assert.AreEqual(0m, rate);
    }

    [Test]
    public void should_qualify_for_free_shipping_when_subtotal_reaches_threshold()
    {
        var order = new Order(new Guid("11111111-2222-3333-4444-555555555555"), "Bela Nagy", 200m);

        Assert.IsTrue(order.QualifiesForFreeShipping());
    }
}
