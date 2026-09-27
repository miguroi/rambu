package id.rambu.prototype;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class ConsentGateTest {
    @Test
    public void recordingRequiresDisclosureConsentAndMicrophonePermission() {
        assertFalse(ConsentGate.mayRecord(false, true));
        assertFalse(ConsentGate.mayRecord(true, false));
        assertTrue(ConsentGate.mayRecord(true, true));
    }
}
