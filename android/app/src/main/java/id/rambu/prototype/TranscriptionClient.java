package id.rambu.prototype;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.MalformedURLException;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import org.json.JSONException;
import org.json.JSONObject;

public final class TranscriptionClient {
    private static final int TIMEOUT_MILLIS = 10 * 60 * 1_000;

    private TranscriptionClient() {}

    public static URL endpointFor(String serverBaseUrl) throws MalformedURLException {
        String normalized = serverBaseUrl.trim();
        while (normalized.endsWith("/")) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        if (!normalized.endsWith("/transcribe")) {
            normalized += "/transcribe";
        }
        return new URL(normalized);
    }

    public static TranscriptionResponse transcribe(String serverBaseUrl, File recording)
        throws IOException {
        HttpURLConnection connection = (HttpURLConnection) endpointFor(serverBaseUrl).openConnection();
        connection.setRequestMethod("POST");
        connection.setRequestProperty("Content-Type", "audio/wav");
        connection.setRequestProperty("X-Rambu-Consent", "true");
        connection.setConnectTimeout(15_000);
        connection.setReadTimeout(TIMEOUT_MILLIS);
        connection.setDoOutput(true);
        connection.setFixedLengthStreamingMode(recording.length());

        try {
            try (
                InputStream fileInput = new FileInputStream(recording);
                OutputStream requestBody = connection.getOutputStream()
            ) {
                byte[] buffer = new byte[16_384];
                int count;
                while ((count = fileInput.read(buffer)) != -1) {
                    requestBody.write(buffer, 0, count);
                }
            }

            int status = connection.getResponseCode();
            InputStream responseStream = status >= 200 && status < 300
                ? connection.getInputStream()
                : connection.getErrorStream();
            String responseBody = readText(responseStream);
            if (status < 200 || status >= 300) {
                throw new IOException(errorMessage(responseBody, status));
            }
            try {
                return TranscriptionResponse.parse(responseBody);
            } catch (JSONException error) {
                throw new IOException("Respons server tidak valid.", error);
            }
        } finally {
            connection.disconnect();
        }
    }

    private static String readText(InputStream stream) throws IOException {
        if (stream == null) {
            return "";
        }
        try (BufferedReader reader = new BufferedReader(
            new InputStreamReader(stream, StandardCharsets.UTF_8)
        )) {
            StringBuilder result = new StringBuilder();
            char[] buffer = new char[4_096];
            int count;
            while ((count = reader.read(buffer)) != -1) {
                result.append(buffer, 0, count);
            }
            return result.toString();
        }
    }

    private static String errorMessage(String body, int status) {
        try {
            return new JSONObject(body).optString("detail", "Server gagal: HTTP " + status);
        } catch (JSONException ignored) {
            return "Server gagal: HTTP " + status;
        }
    }
}
