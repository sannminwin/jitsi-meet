package org.jitsi.meet.sdk.connection_service;

import android.os.Build;
import android.support.annotation.RequiresApi;
import android.telecom.*;

import android.util.*;
import com.facebook.react.bridge.WritableNativeMap;

import org.jitsi.meet.sdk.ReactContextUtils;

import static org.jitsi.meet.sdk.connection_service.ConnectionService.TAG;

/**
 * Connection implementation for Jitsi Meet's {@link ConnectionService}.
 *
 * @author Pawel Domas
 */
@RequiresApi(api = Build.VERSION_CODES.O)
public class ConnectionImpl extends Connection {

    /**
     * The constant which defines the key for the "has video" property. The key
     * is used in the map which carries the call's state passed as the arugment
     * of the {@link RNConnectionService#updateCall} method.
     */
    static final String KEY_HAS_VIDEO = "hasVideo";

    private final ConnectionService service;

    ConnectionImpl(ConnectionService service) {
        this.service = service;
    }

    /**
     * Called when system wants to disconnect the call.
     *
     * {@inheritDoc}
     */
    @Override
    public void onDisconnect() {
        WritableNativeMap data = new WritableNativeMap();
        data.putString("callUUID", getCallUUID());
        ReactContextUtils.emitEvent(
                    null,
                    "org.jitsi.meet:features/connection_service#disconnect",
                    data);
    }

    /**
     * Called when system wants to abort the call.
     *
     * {@inheritDoc}
     */
    @Override
    public void onAbort() {
        WritableNativeMap data = new WritableNativeMap();
        data.putString("callUUID", getCallUUID());
        ReactContextUtils.emitEvent(
                null,
                "org.jitsi.meet:features/connection_service#abort",
                data);
    }

    @Override
    public void onCallAudioStateChanged(CallAudioState state)
    {
        // FIXME update 'selectedDevice' in the AudioMode module
        Log.i(TAG, "onCallAudioStateChanged: " + state);
    }

    /**
     * Unregisters the account when the call is disconnected.
     *
     * @param state - the new connection's state.
     */
    @Override
    public void onStateChanged(int state) {
        super.onStateChanged(state);

        if (state == STATE_DISCONNECTED) {
            ConnectionList.getInstance().remove(this);
            TelecomManager telecom
                = service.getSystemService(TelecomManager.class);
            if (telecom != null) {
                PhoneAccountHandle account = getPhoneAccountHandle();
                if (account != null) {
                    telecom.unregisterPhoneAccount(account);
                }
            }
        }
    }

    /**
     * Retrieves the UUID of the call associated with this connection.
     *
     * @return call UUID
     */
    String getCallUUID() {
        return getExtras().getString(ConnectionService.EXTRAS_CALL_UUID);
    }

    private PhoneAccountHandle getPhoneAccountHandle() {
        return getExtras().getParcelable(
                ConnectionService.EXTRA_PHONE_ACCOUNT_HANDLE);
    }

    @Override
    public String toString() {
        return String.format(
                "ConnectionImpl[adress=%s, uuid=%s]@%d",
                getAddress(), getCallUUID(), hashCode());
    }
}