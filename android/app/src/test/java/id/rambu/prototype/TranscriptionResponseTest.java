package id.rambu.prototype;

import static org.junit.Assert.assertEquals;

import java.net.URL;
import org.junit.Test;

public class TranscriptionResponseTest {
    @Test
    public void parsesIndonesianTranscriptAndAudioStats() throws Exception {
        TranscriptionResponse response = TranscriptionResponse.parse(
            "{\"text\":\"Jangan berikan kode OTP.\",\"language\":\"id\","
                + "\"duration_seconds\":12.5,\"sample_rate\":16000}"
        );

        assertEquals("Jangan berikan kode OTP.", response.text());
        assertEquals("id", response.language());
        assertEquals(12.5, response.durationSeconds(), 0.001);
        assertEquals(16_000, response.sampleRate());
    }

    @Test
    public void endpointAddsTranscribePathWithoutDuplicatingIt() throws Exception {
        assertEquals(
            new URL("http://192.168.1.10:8000/transcribe"),
            TranscriptionClient.endpointFor("http://192.168.1.10:8000/")
        );
        assertEquals(
            new URL("http://192.168.1.10:8000/transcribe"),
            TranscriptionClient.endpointFor("http://192.168.1.10:8000/transcribe")
        );
    }
}
