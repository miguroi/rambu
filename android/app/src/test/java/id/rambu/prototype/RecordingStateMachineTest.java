package id.rambu.prototype;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class RecordingStateMachineTest {
    @Test
    public void allowsOnlyThePrototypeRecordingSequence() {
        RecordingStateMachine state = new RecordingStateMachine();

        assertEquals(RecordingStateMachine.State.IDLE, state.state());
        assertFalse(state.beginTranscription());
        assertTrue(state.beginRecording());
        assertFalse(state.beginRecording());
        assertEquals(RecordingStateMachine.State.RECORDING, state.state());

        assertTrue(state.recordingFinished());
        assertEquals(RecordingStateMachine.State.RECORDED, state.state());
        assertTrue(state.beginTranscription());
        assertEquals(RecordingStateMachine.State.TRANSCRIBING, state.state());

        state.transcriptionFinished();
        assertEquals(RecordingStateMachine.State.RECORDED, state.state());
    }

    @Test
    public void resetReturnsToIdleFromACompletedRecording() {
        RecordingStateMachine state = new RecordingStateMachine();
        state.beginRecording();
        state.recordingFinished();

        state.reset();

        assertEquals(RecordingStateMachine.State.IDLE, state.state());
    }

    @Test
    public void recordingCannotBeDeletedWhileUploadIsReadingIt() {
        RecordingStateMachine state = new RecordingStateMachine();
        state.beginRecording();
        state.recordingFinished();
        assertTrue(state.mayDeleteRecording());

        state.beginTranscription();

        assertFalse(state.mayDeleteRecording());
    }
}
