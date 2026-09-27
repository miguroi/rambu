package id.rambu.prototype;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;
import id.rambu.prototype.audio.SpeakerphoneRecorder;
import java.io.File;
import java.io.IOException;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity {
    private static final int MICROPHONE_PERMISSION_REQUEST = 10;

    private final RecordingStateMachine state = new RecordingStateMachine();
    private final SpeakerphoneRecorder recorder = new SpeakerphoneRecorder();
    private final ExecutorService networkExecutor = Executors.newSingleThreadExecutor();

    private CheckBox consentCheckBox;
    private EditText serverUrlInput;
    private Button startButton;
    private Button stopButton;
    private Button transcribeButton;
    private Button deleteButton;
    private TextView statusText;
    private TextView transcriptText;
    private File recordingFile;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        consentCheckBox = findViewById(R.id.consent_checkbox);
        serverUrlInput = findViewById(R.id.server_url);
        startButton = findViewById(R.id.start_button);
        stopButton = findViewById(R.id.stop_button);
        transcribeButton = findViewById(R.id.transcribe_button);
        deleteButton = findViewById(R.id.delete_button);
        statusText = findViewById(R.id.status_text);
        transcriptText = findViewById(R.id.transcript_text);

        startButton.setOnClickListener(view -> startRecording());
        stopButton.setOnClickListener(view -> stopRecording());
        transcribeButton.setOnClickListener(view -> transcribeRecording());
        deleteButton.setOnClickListener(view -> deleteRecording());
        renderState();
    }

    private void startRecording() {
        boolean permissionGranted = checkSelfPermission(Manifest.permission.RECORD_AUDIO)
            == PackageManager.PERMISSION_GRANTED;
        if (!consentCheckBox.isChecked()) {
            statusText.setText("Konfirmasi persetujuan lawan bicara sebelum merekam.");
            return;
        }
        if (!permissionGranted) {
            requestPermissions(
                new String[] {Manifest.permission.RECORD_AUDIO},
                MICROPHONE_PERMISSION_REQUEST
            );
            statusText.setText("Izinkan mikrofon, lalu tekan Mulai Rekam lagi.");
            return;
        }
        if (!ConsentGate.mayRecord(true, permissionGranted) || !state.beginRecording()) {
            return;
        }

        transcriptText.setText("");
        recordingFile = new File(getCacheDir(), "rambu-speakerphone.wav");
        try {
            recorder.start(recordingFile, new SpeakerphoneRecorder.Listener() {
                @Override
                public void onFinished(File recording, double durationSeconds) {
                    state.recordingFinished();
                    statusText.setText(String.format(
                        Locale.US,
                        "Rekaman siap (%.1f detik). Kirim ke server untuk transkripsi.",
                        durationSeconds
                    ));
                    renderState();
                }

                @Override
                public void onError(String message) {
                    state.reset();
                    recordingFile = null;
                    statusText.setText("Perekaman gagal: " + message);
                    renderState();
                }
            });
            statusText.setText("Sedang merekam mikrofon. Biarkan Rambu tetap terbuka.");
        } catch (IOException | RuntimeException error) {
            state.reset();
            recordingFile = null;
            statusText.setText("Tidak dapat merekam: " + error.getMessage());
        }
        renderState();
    }

    private void stopRecording() {
        if (!recorder.stop()) {
            statusText.setText("Tidak ada perekaman yang sedang berjalan.");
            return;
        }
        statusText.setText("Menyelesaikan file audio…");
        stopButton.setEnabled(false);
    }

    private void transcribeRecording() {
        File audio = recordingFile;
        if (audio == null || !audio.exists() || !state.beginTranscription()) {
            statusText.setText("Rekam percakapan terlebih dahulu.");
            return;
        }
        String serverUrl = serverUrlInput.getText().toString();
        statusText.setText("Mengirim audio dan menunggu Whisper…");
        renderState();

        networkExecutor.execute(() -> {
            try {
                TranscriptionResponse result = TranscriptionClient.transcribe(serverUrl, audio);
                runOnUiThread(() -> {
                    state.transcriptionFinished();
                    transcriptText.setText(result.text().isBlank()
                        ? "(Tidak ada ucapan yang terdeteksi)"
                        : result.text());
                    statusText.setText(String.format(
                        Locale.US,
                        "Selesai: %.1f detik, %d Hz, bahasa %s.",
                        result.durationSeconds(),
                        result.sampleRate(),
                        result.language()
                    ));
                    renderState();
                });
            } catch (IOException error) {
                runOnUiThread(() -> {
                    state.transcriptionFinished();
                    statusText.setText("Transkripsi gagal: " + error.getMessage());
                    renderState();
                });
            }
        });
    }

    private void deleteRecording() {
        if (!state.mayDeleteRecording()) {
            Toast.makeText(this, "Tunggu proses selesai terlebih dahulu.", Toast.LENGTH_SHORT).show();
            return;
        }
        if (recordingFile != null) {
            recordingFile.delete();
        }
        recordingFile = null;
        state.reset();
        transcriptText.setText("");
        statusText.setText("Rekaman lokal telah dihapus.");
        renderState();
    }

    private void renderState() {
        RecordingStateMachine.State current = state.state();
        startButton.setEnabled(current == RecordingStateMachine.State.IDLE);
        stopButton.setEnabled(current == RecordingStateMachine.State.RECORDING);
        transcribeButton.setEnabled(current == RecordingStateMachine.State.RECORDED);
        deleteButton.setEnabled(state.mayDeleteRecording());
        consentCheckBox.setEnabled(current == RecordingStateMachine.State.IDLE);
        serverUrlInput.setEnabled(current != RecordingStateMachine.State.TRANSCRIBING);
    }

    @Override
    public void onRequestPermissionsResult(
        int requestCode,
        String[] permissions,
        int[] grantResults
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == MICROPHONE_PERMISSION_REQUEST
            && (grantResults.length == 0 || grantResults[0] != PackageManager.PERMISSION_GRANTED)) {
            statusText.setText("Izin mikrofon ditolak; Rambu tidak merekam apa pun.");
        }
    }

    @Override
    protected void onDestroy() {
        recorder.shutdown();
        networkExecutor.shutdown();
        super.onDestroy();
    }
}
