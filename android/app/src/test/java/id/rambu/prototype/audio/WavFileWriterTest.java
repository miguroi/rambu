package id.rambu.prototype.audio;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;

import java.io.File;
import java.io.RandomAccessFile;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.Test;

public class WavFileWriterTest {
    @Test
    public void finishingWritesAValidMono16KhzPcmHeader() throws Exception {
        Path directory = Files.createTempDirectory("rambu-wav-test");
        File output = directory.resolve("recording.wav").toFile();
        byte[] pcm = new byte[] {1, 0, 2, 0, 3, 0, 4, 0};

        try (WavFileWriter writer = new WavFileWriter(output, 16_000)) {
            writer.write(pcm, 0, pcm.length);
        }

        byte[] bytes = Files.readAllBytes(output.toPath());
        assertArrayEquals(new byte[] {'R', 'I', 'F', 'F'}, slice(bytes, 0, 4));
        assertArrayEquals(new byte[] {'W', 'A', 'V', 'E'}, slice(bytes, 8, 12));
        assertArrayEquals(new byte[] {'d', 'a', 't', 'a'}, slice(bytes, 36, 40));
        assertEquals(16_000, littleEndianInt(bytes, 24));
        assertEquals(8, littleEndianInt(bytes, 40));
        assertEquals(52, bytes.length);
    }

    @Test
    public void closeUpdatesHeaderAfterMultipleWrites() throws Exception {
        Path directory = Files.createTempDirectory("rambu-wav-test");
        File output = directory.resolve("recording.wav").toFile();

        WavFileWriter writer = new WavFileWriter(output, 16_000);
        writer.write(new byte[] {1, 0}, 0, 2);
        writer.write(new byte[] {2, 0, 3, 0}, 0, 4);
        writer.close();

        try (RandomAccessFile file = new RandomAccessFile(output, "r")) {
            file.seek(4);
            assertEquals(42, Integer.reverseBytes(file.readInt()));
            file.seek(40);
            assertEquals(6, Integer.reverseBytes(file.readInt()));
        }
    }

    private static byte[] slice(byte[] source, int start, int end) {
        byte[] result = new byte[end - start];
        System.arraycopy(source, start, result, 0, result.length);
        return result;
    }

    private static int littleEndianInt(byte[] source, int offset) {
        return (source[offset] & 0xff)
            | ((source[offset + 1] & 0xff) << 8)
            | ((source[offset + 2] & 0xff) << 16)
            | ((source[offset + 3] & 0xff) << 24);
    }
}
