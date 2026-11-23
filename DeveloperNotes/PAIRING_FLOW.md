# Pairing protocol v2

Unpaired phones create independent private QR secrets and advertise their own derived BLE service. Scanning changes only the scanner to the guest role with the scanned secret and a new request UUID. An AES-GCM authenticated request carries its name and request UUID. The advertising phone displays Accept/Decline; neither party sends locations before acceptance.

Accept binds the saved host record to that request UUID and sends accept. The guest accepts only the matching UUID, saves approval, and acknowledges. The host shows Connected only after that matching acknowledgement. The guest shows Connected after a matching accept. Control messages wait for outstanding BLE writes rather than being silently discarded. On reconnect, the saved UUID binds hello/ack; the host can resend acceptance for the same previously approved request. A different request is rejected once approved. No location message can itself create a pairing or connection.

Decline sends a matching rejection and returns the guest to its own QR. Pending requests and accepted pairings persist in Keychain; old protocol records are not automatically approved. Camera permission is declared in Info.plist. External Camera deep links remain supported without a paste-link UI.

Physical-device acceptance checks still required:
- Both phones initially show QR; scanning B with A must show A’s name and Accept/Decline on B. No locations before acceptance.
- Decline: neither paired, guest returns to QR; rescan then accept works.
- Accept: both show Connected; only explicit sharing toggles permit location packets.
- Pause/reconnect, Bluetooth off/on and app relaunch restore an accepted pair without an additional invitation.
- Old/invalid/self QR does not replace a confirmed pairing. Cancel scanner and deny Camera permission recover without a pairing.
- Internet disabled: scanner, invitation, approval and sharing still operate over nearby Bluetooth.

Source parses as Swift; no iOS compiler/Bluetooth devices are available here, so runtime tests above are not marked passed.

## Invitation delivery repair
Bluetooth restoration IDs now include the derived service UUID so a different QR cannot inherit another pairing’s GATT service/remote. Restored peripheral services must match the expected UUID. Missing services/channels trigger discovery/reconnection rather than silently waiting. A foreground three-second retry repeats request/accept messages until the handshake completes. Pending incoming requests can be refreshed by a new request on the authenticated QR channel and are cleared on unsubscribe before acceptance. Progress labels expose the last discovery/write/approval stage without logging names, keys or raw links externally. Device testing remains required.
