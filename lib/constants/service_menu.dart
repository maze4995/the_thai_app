class ServiceItem {
  final String name;
  final int price;
  const ServiceItem(this.name, this.price);
}

const Map<String, List<ServiceItem>> kServiceMenu = {
  '로드회원': [
    ServiceItem('타이 60분', 60000),
    ServiceItem('타이 90분', 80000),
    ServiceItem('아로마 60분', 70000),
    ServiceItem('아로마 90분', 90000),
    ServiceItem('크림 60분', 80000),
    ServiceItem('크림 90분', 100000),
    ServiceItem('스웨디시 60분', 80000),
    ServiceItem('스웨디시 90분', 100000),
  ],
  '어플회원': [
    ServiceItem('타이 60분', 40000),
    ServiceItem('타이 90분', 60000),
    ServiceItem('아로마 60분', 50000),
    ServiceItem('아로마 90분', 70000),
    ServiceItem('크림 60분', 60000),
    ServiceItem('크림 90분', 80000),
    ServiceItem('스웨디시 60분', 70000),
    ServiceItem('스웨디시 90분', 90000),
  ],
};
