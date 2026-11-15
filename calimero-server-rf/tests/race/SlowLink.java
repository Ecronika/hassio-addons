package race;
import tuwien.auto.calimero.link.medium.TPSettings;
import tuwien.auto.calimero.server.VirtualLink;
/** Simuliert ein langsam oeffnendes Interface (wie USB) und zaehlt Oeffnungsversuche. */
public class SlowLink extends VirtualLink {
	static final java.util.concurrent.atomic.AtomicInteger opens = new java.util.concurrent.atomic.AtomicInteger();
	public SlowLink(final Object[] args) throws InterruptedException {
		super("slow", new TPSettings());
		final int n = opens.incrementAndGet();
		System.out.println("RACETEST open #" + n + " in " + Thread.currentThread().getName());
		Thread.sleep(3000);
		System.out.println("RACETEST open #" + n + " done");
	}
}
