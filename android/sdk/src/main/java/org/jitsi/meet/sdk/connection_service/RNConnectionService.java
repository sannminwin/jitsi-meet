package org.jitsi.meet.sdk.connection_service;

import android.annotation.SuppressLint;
import android.content.Context;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.support.annotation.RequiresApi;
import android.telecom.DisconnectCause;
import android.telecom.PhoneAccount;
import android.telecom.PhoneAccountHandle;
import android.telecom.TelecomManager;
import android.telecom.VideoProfile;

import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.ReadableMap;

import java.util.*;

/**
 * The react-native side of Jitsi Meet's {@link ConnectionService}. Exposes
 * the Java Script API.
 *
 * @author Pawel Domas
 */
@RequiresApi(api = Build.VERSION_CODES.O)
public class RNConnectionService
        extends ReactContextBaseJavaModule {

    public RNConnectionService(ReactApplicationContext reactContext) {
        super(reactContext);
    }

    /**
     * Starts a new outgoing call.
     *
     * @param callUUID - unique call identifier assigned by Jitsi Meet to
     *        a conference call.
     * @param handle - a call handle which by default is Jitsi Meet room's URL.
     * @param hasVideo - whether or not user starts with the video turned on.
     * @param promise - the Promise instance passed by the React-native bridge,
     *        so that this method returns a Promise on the JS side.
     *
     * NOTE regarding the "missingPermission" suppress - SecurityException will
     * be handled as part of the Exception try catch block and the Promise will
     * be rejected.
     */
    @SuppressLint("MissingPermission")
    @ReactMethod
    public void startCall(
            String callUUID,
            String handle,
            boolean hasVideo,
            Promise promise) {

        ReactApplicationContext ctx = getReactApplicationContext();

        Uri address = Uri.fromParts(PhoneAccount.SCHEME_SIP, handle, null);
        PhoneAccountHandle accountHandle
            = ConnectionService.registerPhoneAccount(
                    getReactApplicationContext(), address, callUUID);

        Bundle extras = new Bundle();
        extras.putParcelable(
                TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE,
                accountHandle);
        extras.putInt(
            TelecomManager.EXTRA_START_CALL_WITH_VIDEO_STATE,
            hasVideo
                ? VideoProfile.STATE_BIDIRECTIONAL
                : VideoProfile.STATE_AUDIO_ONLY);

        Bundle outgoingCallExtras = new Bundle();
        outgoingCallExtras.putString(
            ConnectionService.EXTRAS_CALL_UUID, callUUID);
        extras.putParcelable(
            TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS, outgoingCallExtras);

        ConnectionList
            .getInstance()
            .registerStartCallPromise(callUUID, promise);

        try {
            TelecomManager tm
                = (TelecomManager) ctx.getSystemService(
                        Context.TELECOM_SERVICE);

            tm.placeCall(address, extras);
        } catch (Exception e) {
            ConnectionList.getInstance().unregisterStartCallPromise(callUUID);
            promise.reject(e);
        }
    }

    /**
     * Called by the JS side of things to mark the call as failed.
     *
     * @param callUUID - the call's UUID.
     */
    @ReactMethod
    public void reportCallFailed(String callUUID) {
        ConnectionList
                .getInstance()
                .setConnectionDisconnected(
                    callUUID, new DisconnectCause(DisconnectCause.ERROR));
    }

    /**
     * Called by the JS side of things to mark the call as disconnected.
     *
     * @param callUUID - the call's UUID.
     */
    @ReactMethod
    public void endCall(String callUUID) {
        ConnectionList
                .getInstance()
                .setConnectionDisconnected(
                    callUUID, new DisconnectCause(DisconnectCause.LOCAL));
    }

    /**
     * Called by the JS side of things to mark the call as active.
     *
     * @param callUUID - the call's UUID.
     */
    @ReactMethod
    public void reportConnectedOutgoingCall(String callUUID) {
        ConnectionList
                .getInstance()
                .setConnectionActive(callUUID);
    }

    @Override
    public String getName() {
        return "ConnectionService";
    }

    /**
     * Called by the JS side to update the call's state.
     *
     * @param callUUID - the call's UUID.
     * @param callState - the map which carries infor about the current call's
     *        state. See static fields in {@link ConnectionImpl} prefixed with
     *        "KEY_" for the values supported by the Android implementation.
     */
    @ReactMethod
    public void updateCall(String callUUID, ReadableMap callState) {
        ConnectionList
            .getInstance()
            .updateCall(callUUID, callState);
    }

    static public boolean isAudioRouteConfigurable() {
        return ConnectionList.getInstance().size() > 0;
    }

    static public void setAudioRoute(int audioRoute) {
        List<ConnectionImpl> connections
            = ConnectionList.getInstance().getAll();
        for (ConnectionImpl c : connections) {
            c.setAudioRoute(audioRoute);
        }
    }
}
