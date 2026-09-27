package id.rambu.prototype;

import org.json.JSONException;
import org.json.JSONObject;

public record TranscriptionResponse(
    String text,
    String language,
    double durationSeconds,
    int sampleRate
) {
    public static TranscriptionResponse parse(String json) throws JSONException {
        JSONObject object = new JSONObject(json);
        return new TranscriptionResponse(
            object.getString("text"),
            object.getString("language"),
            object.getDouble("duration_seconds"),
            object.getInt("sample_rate")
        );
    }
}
