package com.mknoon.app.pipproof;

import android.app.Activity;
import android.content.Context;
import android.graphics.Color;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Process;
import android.util.Log;
import android.widget.TextView;
import java.util.regex.Pattern;

/** Test-APK-only foreground owner that deterministically takes media audio focus. */
public final class PictureInPictureAudioFocusInterruptionProofActivity extends Activity {
  private static final String TAG = "MknoonPiPInterrupt";
  private static final String NONCE_EXTRA = "proofNonce";
  private static final Pattern NONCE_PATTERN = Pattern.compile("^[0-9a-f]{32}$");

  private final AudioManager.OnAudioFocusChangeListener focusChangeListener = change -> { };
  private AudioManager audioManager;
  private AudioFocusRequest focusRequest;
  private boolean focusAttempted;

  @Override
  public void onCreate(Bundle state) {
    super.onCreate(state);
    audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
    TextView view = new TextView(this);
    view.setBackgroundColor(Color.BLACK);
    view.setTextColor(Color.WHITE);
    view.setTextSize(18);
    view.setText("Mknoon PiP audio-focus interruption proof");
    view.setPadding(32, 64, 32, 32);
    setContentView(view);
  }

  @Override
  public void onWindowFocusChanged(boolean hasFocus) {
    super.onWindowFocusChanged(hasFocus);
    if (hasFocus && !focusAttempted) {
      focusAttempted = true;
      requestProofFocus();
    }
  }

  private void requestProofFocus() {
    String nonce = getIntent().getStringExtra(NONCE_EXTRA);
    if (nonce == null || !NONCE_PATTERN.matcher(nonce).matches()) {
      Log.e(TAG, "[MKNOON_PIP_INTERRUPT] FOCUS_REQUEST_REJECTED reason=bad_nonce");
      finishAndRemoveTask();
      return;
    }
    AudioAttributes attributes = new AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
        .build();
    int result;
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      focusRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
          .setAudioAttributes(attributes)
          .setOnAudioFocusChangeListener(focusChangeListener)
          .build();
      result = audioManager.requestAudioFocus(focusRequest);
    } else {
      @SuppressWarnings("deprecation")
      int legacyResult = audioManager.requestAudioFocus(
          focusChangeListener,
          AudioManager.STREAM_MUSIC,
          AudioManager.AUDIOFOCUS_GAIN);
      result = legacyResult;
    }
    String settlement = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        ? "granted"
        : "denied";
    Log.i(
        TAG,
        "[MKNOON_PIP_INTERRUPT] FOCUS_REQUEST nonce=" + nonce
            + " gain=GAIN usage=USAGE_MEDIA content=CONTENT_TYPE_MOVIE result="
            + settlement + " uid=" + Process.myUid());
  }

  @Override
  protected void onDestroy() {
    if (audioManager != null) {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && focusRequest != null) {
        audioManager.abandonAudioFocusRequest(focusRequest);
      } else {
        @SuppressWarnings("deprecation")
        int ignored = audioManager.abandonAudioFocus(focusChangeListener);
      }
    }
    focusRequest = null;
    super.onDestroy();
  }
}
