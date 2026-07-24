/*
 * Copyright @ 2017-present 8x8, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.jitsi.meet;

import android.content.ActivityNotFoundException;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.RestrictionsManager;
import android.net.Uri;
import android.os.Bundle;
import android.provider.Settings;
import android.util.Log;
import android.view.KeyEvent;
import android.view.View;

import androidx.annotation.Nullable;

import org.jitsi.meet.sdk.JitsiMeet;
import org.jitsi.meet.sdk.JitsiMeetActivity;
import org.jitsi.meet.sdk.JitsiMeetConferenceOptions;

import java.lang.reflect.Method;
import java.net.MalformedURLException;
import java.net.URL;
import java.util.HashMap;

/**
 * The one and only Activity that the Jitsi Meet app needs. The
 * {@code Activity} is launched in {@code singleTask} mode, so it will be
 * created upon application initialization and there will be a single instance
 * of it. Further attempts at launching the application once it was already
 * launched will result in {@link MainActivity#onNewIntent(Intent)} being called.
 */
public class MainActivity extends JitsiMeetActivity {
    /**
     * The request code identifying requests for the permission to draw on top
     * of other apps. The value must be 16-bit and is arbitrarily chosen here.
     */
    private static final int OVERLAY_PERMISSION_REQUEST_CODE
        = (int) (Math.random() * Short.MAX_VALUE);

    /**
     * ServerURL configuration key for restriction configuration using {@link android.content.RestrictionsManager}
     */
    public static final String RESTRICTION_SERVER_URL = "SERVER_URL";

    /**
     * Broadcast receiver for restrictions handling
     */
    private BroadcastReceiver broadcastReceiver;

    /**
     * Flag if configuration is provided by RestrictionManager
     */
    private boolean configurationByRestrictions = false;

    /**
     * Default URL as could be obtained from RestrictionManager
     */
    private String defaultURL = BuildConfig.BMJ_SERVER_URL;

    /**
     * True after the local user has actually joined a conference.
     */
    private boolean conferenceWasJoined;

    /**
     * Prevents duplicate browser launches when close events arrive in sequence.
     */
    private boolean exitRedirectHandled;


    // JitsiMeetActivity overrides
    //

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setIntent(normalizeConferenceIntent(getIntent()));
        JitsiMeet.showSplashScreen(this);
        super.onCreate(null);
    }

    @Override
    protected boolean extraInitialize() {
        Log.d(this.getClass().getSimpleName(), "LIBRE_BUILD="+BuildConfig.LIBRE_BUILD);

        // Setup Crashlytics and Firebase Dynamic Links
        // Here we are using reflection since it may have been disabled at compile time.
        try {
            Class<?> cls = Class.forName("org.jitsi.meet.GoogleServicesHelper");
            Method m = cls.getMethod("initialize", JitsiMeetActivity.class);
            m.invoke(null, this);
        } catch (Exception e) {
            // Ignore any error, the module is not compiled when LIBRE_BUILD is enabled.
        }

        // In Debug builds React needs permission to write over other apps in
        // order to display the warning and error overlays.
        if (BuildConfig.DEBUG) {
            if (!Settings.canDrawOverlays(this)) {
                Intent intent
                    = new Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:" + getPackageName()));

                startActivityForResult(intent, OVERLAY_PERMISSION_REQUEST_CODE);

                return true;
            }
        }

        return false;
    }

    @Override
    protected void initialize() {
        broadcastReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                // As new restrictions including server URL are received,
                // conference should be restarted with new configuration.
                leave();
                recreate();
            }
        };
        registerReceiver(broadcastReceiver,
            new IntentFilter(Intent.ACTION_APPLICATION_RESTRICTIONS_CHANGED));

        resolveRestrictions();
        setJitsiMeetConferenceDefaultOptions();
        super.initialize();
    }

    @Override
    public void onDestroy() {
        if (broadcastReceiver != null) {
            unregisterReceiver(broadcastReceiver);
            broadcastReceiver = null;
        }

        super.onDestroy();
    }

    private void setJitsiMeetConferenceDefaultOptions() {
        // Set default options
        JitsiMeetConferenceOptions defaultOptions
            = new JitsiMeetConferenceOptions.Builder()
            .setServerURL(buildURL(defaultURL))
            .setFeatureFlag("welcomepage.enabled", true)
            .setFeatureFlag("call-integration.enabled", false)
            .setFeatureFlag("resolution", 360)
            .setFeatureFlag("server-url-change.enabled", false)
            .build();
        JitsiMeet.setDefaultConferenceOptions(defaultOptions);
    }

    @Override
    protected void onConferenceWillJoin(HashMap<String, Object> extraData) {
        conferenceWasJoined = false;
        exitRedirectHandled = false;
        super.onConferenceWillJoin(extraData);
    }

    @Override
    protected void onConferenceJoined(HashMap<String, Object> extraData) {
        conferenceWasJoined = true;
        super.onConferenceJoined(extraData);
    }

    @Override
    protected void onConferenceTerminated(HashMap<String, Object> extraData) {
        super.onConferenceTerminated(extraData);
        returnToTotem();
    }

    @Override
    protected void onReadyToClose() {
        if (!returnToTotem()) {
            super.onReadyToClose();
        }
    }

    /**
     * Opens the configured totem page in Google Chrome after leaving a joined conference.
     * Falls back to the default browser when Chrome is not installed.
     *
     * @return true if a browser was launched, false otherwise.
     */
    private boolean returnToTotem() {
        if (!conferenceWasJoined || exitRedirectHandled) {
            return false;
        }

        exitRedirectHandled = true;

        final View decorView = getWindow().getDecorView();
        decorView.setVisibility(View.INVISIBLE);

        Intent browserIntent = new Intent(
            Intent.ACTION_VIEW,
            Uri.parse(BuildConfig.BMJ_EXIT_URL));

        browserIntent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK
                | Intent.FLAG_ACTIVITY_CLEAR_TOP
                | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        browserIntent.setPackage("com.android.chrome");

        try {
            startActivity(browserIntent);
        } catch (ActivityNotFoundException chromeNotAvailable) {
            browserIntent.setPackage(null);

            try {
                startActivity(browserIntent);
            } catch (ActivityNotFoundException browserNotAvailable) {
                decorView.setVisibility(View.VISIBLE);
                exitRedirectHandled = false;
                Log.e(TAG, "No browser available for BMJ exit URL", browserNotAvailable);
                return false;
            }
        }

        overridePendingTransition(0, 0);
        finishAndRemoveTask();
        return true;
    }

    /**
     * Converts the dedicated browser App Link into the actual Jitsi room URL.
     *
     * The browser owns /musei-in-diretta?bmj_totem=1, while the application
     * exclusively owns /app/musei-in-diretta.
     */
    private Intent normalizeConferenceIntent(Intent intent) {
        if (intent == null || !Intent.ACTION_VIEW.equals(intent.getAction())) {
            return intent;
        }

        Uri uri = intent.getData();

        if (uri == null
                || !"https".equalsIgnoreCase(uri.getScheme())
                || !BuildConfig.BMJ_APP_LINK_HOST.equalsIgnoreCase(uri.getHost())
                || !BuildConfig.BMJ_APP_LINK_PATH.equals(uri.getPath())) {
            return intent;
        }

        String encodedFragment = uri.getEncodedFragment();
        boolean displayNameFragmentAccepted =
            isAllowedDisplayNameFragment(encodedFragment);

        Uri.Builder conferenceUriBuilder = uri.buildUpon()
            .path(BuildConfig.BMJ_CONFERENCE_PATH)
            .clearQuery()
            .fragment(null);

        if (displayNameFragmentAccepted) {
            conferenceUriBuilder.encodedFragment(encodedFragment);
        }

        Uri conferenceUri = conferenceUriBuilder.build();

        Intent normalizedIntent = new Intent(intent);
        normalizedIntent.setData(conferenceUri);

        Uri conferenceUriWithoutFragment = conferenceUri.buildUpon()
            .fragment(null)
            .build();

        Log.i(
            TAG,
            "Normalized BMJ App Link to conference URL: "
                + conferenceUriWithoutFragment
                + " displayNameFragment="
                + (displayNameFragmentAccepted ? "accepted" : "discarded"));

        return normalizedIntent;
    }

    /**
     * Preserves only the encoded userInfo.displayName fragment generated by the
     * museum gate. Every other fragment is discarded before Jitsi receives it.
     */
    private boolean isAllowedDisplayNameFragment(
            @Nullable String encodedFragment) {
        final String prefix = "userInfo.displayName=";

        if (encodedFragment == null
                || encodedFragment.length() > 1024
                || !encodedFragment.startsWith(prefix)
                || encodedFragment.indexOf('&') >= 0) {
            return false;
        }

        String jsonDisplayName = Uri.decode(
            encodedFragment.substring(prefix.length()));

        if (jsonDisplayName.length() < 4
                || jsonDisplayName.length() > 123
                || jsonDisplayName.charAt(0) != '"'
                || jsonDisplayName.charAt(
                    jsonDisplayName.length() - 1) != '"') {
            return false;
        }

        String displayName = jsonDisplayName.substring(
            1,
            jsonDisplayName.length() - 1);

        return displayName.matches(
            "^(?=.{2,121}$)[\\p{L}\\p{M}]"
                + "[\\p{L}\\p{M} .'-]*$");
    }

    @Override
    public void onNewIntent(Intent intent) {
        Intent normalizedIntent = normalizeConferenceIntent(intent);

        setIntent(normalizedIntent);
        super.onNewIntent(normalizedIntent);
    }

    private void resolveRestrictions() {
        RestrictionsManager manager =
            (RestrictionsManager) getSystemService(Context.RESTRICTIONS_SERVICE);
        Bundle restrictions = manager.getApplicationRestrictions();

        defaultURL = BuildConfig.BMJ_SERVER_URL;
        configurationByRestrictions = false;

        if (restrictions == null
                || !restrictions.containsKey(RESTRICTION_SERVER_URL)) {
            return;
        }

        String restrictedServerURL =
            restrictions.getString(RESTRICTION_SERVER_URL);

        if (isValidRestrictedServerURL(restrictedServerURL)) {
            defaultURL = restrictedServerURL;
            configurationByRestrictions = true;
        } else {
            Log.w(
                TAG,
                "Ignoring invalid managed SERVER_URL restriction");
        }
    }

    /**
     * Managed configuration may override the build server only with a complete
     * HTTPS origin. Paths, queries, fragments and user information are rejected.
     */
    private boolean isValidRestrictedServerURL(@Nullable String value) {
        if (value == null || value.trim().isEmpty()) {
            return false;
        }

        Uri uri = Uri.parse(value.trim());
        String path = uri.getPath();

        return "https".equalsIgnoreCase(uri.getScheme())
            && uri.getHost() != null
            && !uri.getHost().isEmpty()
            && (path == null || path.isEmpty() || "/".equals(path))
            && uri.getQuery() == null
            && uri.getFragment() == null
            && uri.getUserInfo() == null;
    }

    // Activity lifecycle method overrides
    //

    @Override
    public void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == OVERLAY_PERMISSION_REQUEST_CODE) {
            if (Settings.canDrawOverlays(this)) {
                initialize();
                return;
            }

            throw new RuntimeException("Overlay permission is required when running in Debug mode.");
        }

        super.onActivityResult(requestCode, resultCode, data);
    }

    // ReactAndroid/src/main/java/com/facebook/react/ReactActivity.java
    @Override
    public boolean onKeyUp(int keyCode, KeyEvent event) {
        if (BuildConfig.DEBUG && keyCode == KeyEvent.KEYCODE_MENU) {
            JitsiMeet.showDevOptions();
            return true;
        }

        return super.onKeyUp(keyCode, event);
    }

    @Override
    public void onPictureInPictureModeChanged(boolean isInPictureInPictureMode) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode);

        Log.d(TAG, "Is in picture-in-picture mode: " + isInPictureInPictureMode);

        if (!isInPictureInPictureMode) {
            this.startActivity(new Intent(this, getClass())
                .addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT));
        }
    }

    // Helper methods
    //

    private @Nullable URL buildURL(String urlStr) {
        try {
            return new URL(urlStr);
        } catch (MalformedURLException e) {
            return null;
        }
    }
}
