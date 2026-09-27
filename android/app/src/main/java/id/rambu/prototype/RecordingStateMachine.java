package id.rambu.prototype;

public final class RecordingStateMachine {
    public enum State { IDLE, RECORDING, RECORDED, TRANSCRIBING }

    private State state = State.IDLE;

    public State state() {
        return state;
    }

    public boolean beginRecording() {
        if (state != State.IDLE) {
            return false;
        }
        state = State.RECORDING;
        return true;
    }

    public boolean recordingFinished() {
        if (state != State.RECORDING) {
            return false;
        }
        state = State.RECORDED;
        return true;
    }

    public boolean beginTranscription() {
        if (state != State.RECORDED) {
            return false;
        }
        state = State.TRANSCRIBING;
        return true;
    }

    public void transcriptionFinished() {
        if (state == State.TRANSCRIBING) {
            state = State.RECORDED;
        }
    }

    public boolean mayDeleteRecording() {
        return state == State.RECORDED;
    }

    public void reset() {
        state = State.IDLE;
    }
}
