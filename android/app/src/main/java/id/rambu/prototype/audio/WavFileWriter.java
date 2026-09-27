package id.rambu.prototype.audio;

import java.io.Closeable;
import java.io.File;
import java.io.IOException;
import java.io.RandomAccessFile;

public final class WavFileWriter implements Closeable {
    private static final int HEADER_SIZE = 44;

    private final RandomAccessFile output;
    private final int sampleRate;
    private int dataLength;
    private boolean closed;

    public WavFileWriter(File file, int sampleRate) throws IOException {
        this.sampleRate = sampleRate;
        output = new RandomAccessFile(file, "rw");
        output.setLength(0);
        output.write(new byte[HEADER_SIZE]);
    }

    public synchronized void write(byte[] data, int offset, int length) throws IOException {
        if (closed) {
            throw new IOException("Writer already closed");
        }
        output.write(data, offset, length);
        dataLength += length;
    }

    @Override
    public synchronized void close() throws IOException {
        if (closed) {
            return;
        }
        output.seek(0);
        writeAscii("RIFF");
        writeLittleEndianInt(36 + dataLength);
        writeAscii("WAVE");
        writeAscii("fmt ");
        writeLittleEndianInt(16);
        writeLittleEndianShort(1);
        writeLittleEndianShort(1);
        writeLittleEndianInt(sampleRate);
        writeLittleEndianInt(sampleRate * 2);
        writeLittleEndianShort(2);
        writeLittleEndianShort(16);
        writeAscii("data");
        writeLittleEndianInt(dataLength);
        closed = true;
        output.close();
    }

    private void writeAscii(String value) throws IOException {
        output.writeBytes(value);
    }

    private void writeLittleEndianInt(int value) throws IOException {
        output.writeInt(Integer.reverseBytes(value));
    }

    private void writeLittleEndianShort(int value) throws IOException {
        output.writeShort(Short.reverseBytes((short) value));
    }
}
