package com.davidmartos96.sqflite_sqlcipher.dev;

import android.util.Log;

import static android.content.ContentValues.TAG;

/**
 * Created by alex on 09/01/18.
 */

public final class Debug {

    /** Immutable source-time switch for unusually verbose value-type logging. */
    public static final boolean EXTRA_LOGV_ENABLED = false;

    private Debug() {
    }

    // Deprecated to prevent usage
    @Deprecated
    public static void devLog(String tag, String message) {
        Log.d(TAG, message);
    }
}
