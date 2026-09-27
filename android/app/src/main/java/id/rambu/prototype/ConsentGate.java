package id.rambu.prototype;

public final class ConsentGate {
    private ConsentGate() {}

    public static boolean mayRecord(boolean consentConfirmed, boolean microphoneGranted) {
        return consentConfirmed && microphoneGranted;
    }
}
