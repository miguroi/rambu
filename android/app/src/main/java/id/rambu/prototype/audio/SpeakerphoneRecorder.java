package id.rambu.prototype.audio;

import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import java.io.File;
import java.io.IOException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

public final class SpeakerphoneRecorder {
    public interface Listener {
        void onFinished(File recording, double durationSeconds);
        void onError(String message);
    }

    private static final int SAMPLE_RATE = 16_000;

    private final AtomicBoolean capturing = new AtomicBoolean(false);
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private AudioRecord audioRecord;

    public void start(File destination, Listener listener) throws IOException, SecurityException {
        if (!capturing.compareAndSet(false, true)) {
            throw new IllegalStateException("Recording already active");
        }

        int minimum = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        );
        if (minimum <= 0) {
            capturing.set(false);
            throw new IOException("Perangkat tidak mendukung format rekaman yang dibutuhkan.");
        }
        int bufferSize = Math.max(minimum * 2, 8_192);

        AudioFormat format = new AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(SAMPLE_RATE)
            .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
            .build();
        audioRecord = new AudioRecord.Builder()
            .setAudioSource(MediaRecorder.AudioSource.MIC)
            .setAudioFormat(format)
            .setBufferSizeInBytes(bufferSize)
            .build();
        if (audioRecord.getState() != AudioRecord.STATE_INITIALIZED) {
            audioRecord.release();
            audioRecord = null;
            capturing.set(false);
            throw new IOException("Mikrofon tidak dapat dimulai saat ini.");
        }

        WavFileWriter writer;
        try {
            writer = new WavFileWriter(destination, SAMPLE_RATE);
            audioRecord.startRecording();
        } catch (IOException | RuntimeException error) {
            audioRecord.release();
            audioRecord = null;
            capturing.set(false);
            destination.delete();
            throw error;
        }

        AudioRecord activeRecorder = audioRecord;
        long startedAt = SystemClock.elapsedRealtime();
        executor.execute(() -> captureLoop(
            activeRecorder,
            writer,
            destination,
            bufferSize,
            startedAt,
            listener
        ));
    }

    public boolean stop() {
        return capturing.compareAndSet(true, false);
    }

    public void shutdown() {
        stop();
        executor.shutdown();
    }

    private void captureLoop(
        AudioRecord recorder,
        WavFileWriter writer,
        File destination,
        int bufferSize,
        long startedAt,
        Listener listener
    ) {
        String errorMessage = null;
        byte[] buffer = new byte[bufferSize];
        try {
            while (capturing.get()) {
                int count = recorder.read(buffer, 0, buffer.length);
                if (count > 0) {
                    writer.write(buffer, 0, count);
                } else if (count < 0) {
                    throw new IOException("Pembacaan mikrofon gagal: " + count);
                }
            }
        } catch (IOException | RuntimeException error) {
            errorMessage = error.getMessage() == null
                ? "Perekaman gagal."
                : error.getMessage();
        } finally {
            capturing.set(false);
            try {
                if (recorder.getRecordingState() == AudioRecord.RECORDSTATE_RECORDING) {
                    recorder.stop();
                }
            } catch (RuntimeException ignored) {
                // Release still runs below.
            }
            recorder.release();
            audioRecord = null;
            try {
                writer.close();
            } catch (IOException closeError) {
                if (errorMessage == null) {
                    errorMessage = closeError.getMessage();
                }
            }
        }

        String finalError = errorMessage;
        double duration = (SystemClock.elapsedRealtime() - startedAt) / 1_000.0;
        mainHandler.post(() -> {
            if (finalError == null) {
                listener.onFinished(destination, duration);
            } else {
                destination.delete();
                listener.onError(finalError);
            }
        });
    }
}
