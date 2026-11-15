package race;
import java.net.InetSocketAddress;
import tuwien.auto.calimero.link.KNXNetworkLinkIP;
import tuwien.auto.calimero.link.medium.TPSettings;
public class Client {
	public static void main(String[] a) throws Exception {
		Thread.sleep(Long.parseLong(a[0]));
		for (int i = 1; i <= 8; i++) {
			try (var l = KNXNetworkLinkIP.newTunnelingLink(new InetSocketAddress("127.0.0.1", 0), new InetSocketAddress("127.0.0.1", 13671), false, new TPSettings())) {
				System.out.println("RACETEST client connected on attempt " + i);
				Thread.sleep(1000);
				return;
			} catch (Exception e) { System.out.println("RACETEST client attempt " + i + " failed: " + e.getMessage()); Thread.sleep(500); }
		}
	}
}
