# NBOS - Prosmart - Omni API Esleme

NBOS bu projede calistirilacak sistem degil, ekran ve menu referansidir.
Prosmart, NBOS'taki surecleri modern Flutter arayuzuyle yeniden kurar.
Omni API ise canli veri ve operasyon kaynagidir.

## Omni API yapisi

- Kimlik dogrulama: `/api/TokenAuth/Authenticate`
- ABP servis formati: `/api/services/app/{Service}/{Method}`
- Swagger UI runtime'da uretilir; repodaki dokuman kopyasinda statik swagger JSON yoktur.

## Ilk servis eslemeleri

| Prosmart modul tipi | NBOS ref ornekleri | Omni servis | Ana metot |
| --- | --- | --- | --- |
| Finans belge yonetimi | `insert_irsaliye_fatura`, `find_fatura`, `odeme`, `insert_banka_talimat` | `Invoice` | `GetInvoiceData` |
| Stok ve depo yonetimi | `stok_haraketleri`, `eldeki_stok`, `insert_sayim_fisi`, `insert_transfer_fisi` | `FicheStock` | `GetFicheList` |
| Satinalma ve siparis | `satinalim_talepler`, `satinalim_siparisler`, `list_satinalim_siparis` | `OrderItem` | `GetOrders` |
| Raporlar | `ps_cash_reports`, `ps_stock_reports`, `ps_cost_analysis` | `Report` | `GetDashboardData` |
| Servis ve bakim | `insert_musteri_sikayeti`, `servis_girisi`, `find_bakim_takip` | `WorkOrder` | `GetAllWorkOrderData` |
| Yetki ve kullanici | `insert_kullanici`, `insert_kullanici_yetki`, `insert_grup` | `User` | `GetAllUsers` |
| Satis/ticari surecler | `insert_teklif`, `find_satis_firsati`, `insert_sozlesme` | `Customer` | `GetCustomers` |

## Uygulama stratejisi

1. NBOS menu XML'i Prosmart rotalarina map edilir.
2. Prosmart ekranlari tek tek Flutter-native akislara cevrilir.
3. Ekranlar once demo veriyle calisir, sonra ayni model Omni servisinden beslenir.
4. Omni API baglantisi `OMNI_API_BASE_URL` ile verilir.
5. API cagri formatlari `lib/app/omni_client.dart` icinde merkezi tutulur.
