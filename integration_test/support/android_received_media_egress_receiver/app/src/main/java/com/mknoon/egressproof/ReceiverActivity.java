package com.mknoon.egressproof;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.widget.TextView;
import java.io.InputStream;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;

public final class ReceiverActivity extends Activity {
  @Override public void onCreate(Bundle state) { super.onCreate(state); render(getIntent()); }
  @Override public void onNewIntent(Intent intent) { super.onNewIntent(intent); render(intent); }

  private void render(Intent intent) {
    List<Uri> uris = new ArrayList<>();
    if (Intent.ACTION_SEND_MULTIPLE.equals(intent.getAction())) {
      ArrayList<Uri> many = intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM);
      if (many != null) uris.addAll(many);
    } else {
      Uri one = intent.getParcelableExtra(Intent.EXTRA_STREAM);
      if (one != null) uris.add(one);
    }
    StringBuilder truth = new StringBuilder("count=").append(uris.size());
    for (int i = 0; i < uris.size(); i++) truth.append("\n").append(i).append(": ").append(hash(uris.get(i)));
    TextView view = new TextView(this); view.setTextSize(18); view.setPadding(32, 64, 32, 32); view.setText(truth); setContentView(view);
  }

  private String hash(Uri uri) {
    try (InputStream input = getContentResolver().openInputStream(uri)) {
      MessageDigest digest = MessageDigest.getInstance("SHA-256");
      byte[] buffer = new byte[8192]; int read;
      while ((read = input.read(buffer)) != -1) digest.update(buffer, 0, read);
      StringBuilder value = new StringBuilder(); for (byte b : digest.digest()) value.append(String.format("%02x", b));
      return value.toString();
    } catch (Exception ignored) { return "UNREADABLE"; }
  }
}
