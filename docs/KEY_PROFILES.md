# Key formats and manufacturer flows

Sources checked on 2026-10-29. A format constraint does not predict a key bound
cryptographically to a device. All examples below are **synthetic and have no
unlock validity**. No profile is automatically selected from a brand, product
name, or fastboot command detection.

## Experimental text profiles

Select one with `--key-profile <id> --allow-experimental`. The opt-in is required
again when resuming a saved named profile. Explicit `--pattern` / `--patterns`
remain available for user-defined masks; they cannot accompany `--key-profile`.

| ID | Mask | Scope and evidence | Synthetic example |
|---|---|---|---|
| `motorola-20` | `X{20}` | [Dan Rosenberg's original research](https://vulnfactory.org/motopocalypse.html) describes a 20-character token in the context of Atrix HD, Razr HD and Razr M and their developer-edition flow. The uppercase alphanumeric alphabet is an experimental hypothesis, not established for every Motorola model. | `AB12CD34EF56GH78IJ90` |
| `sony-xperia-16` | `H{16}` | The [Sony Open Devices portal](https://opendevices.sony.net/aosp-on-xperia-open-devices/get-started/unlock-bootloader) generates codes from IMEI, IDID or MEID for supported Xperia devices. This source does not establish a universal 16-hex-character format; the mask is experimental. Eligibility depends on the exact model/variant. | `0123456789ABCDEF` |
| `huawei-honor-legacy-16` | `9{16}` | Historical Huawei/Honor hypothesis only: 16 decimal digits are not asserted for current Honor products or every historical model. [Huawei's support response](https://consumer.huawei.com/en/community/details/topicId-76277/) reports that code applications ended on July 25, 2018. No model is certified compatible by this profile. | `1234567890123456` |

All three profiles have weight 1. Weights only express scheduling preference;
they are not observed success probabilities. Unsupported Motorola digit-position
hypotheses and unrelated six/eight-digit PINs have been removed from the built-in
schedule. Without explicit masks/profile, the generator uses `?{length}` with the
selected `--type`; the legacy name `moto` is only a charset alias.

## Documented flows without generator masks

These flows are references, not new integrations. Account workflows, external
vendor tools and binary token handling are outside this implementation. The
existing fastboot transport is unchanged, including its command formatting; a
key profile does not add a vendor-specific prefix or guarantee transport support.

| Family / exact scope | Reference and treatment |
|---|---|
| Google Pixel / Nexus | [AOSP Fastboot guide](https://source.android.google.cn/docs/setup/test/running?hl=en) documents `fastboot flashing unlock` on supported newer devices and `fastboot oem unlock` on older devices. No textual key mask; OEM unlock eligibility still applies. |
| OnePlus 5 (`cheeseburger`) | [LineageOS device guide](https://lineageos.github.io/lineage_wiki/devices/cheeseburger/install/) uses `fastboot oem unlock` without a key. Do not generalize to every OnePlus. |
| OnePlus T-Mobile variants | [OnePlus token portal](https://www.oneplus.com/us/unlock_token) explicitly limits its service to T-Mobile Edition devices and requests device identifiers. No universal textual pattern, no binary-token generation or upload here. |
| Xiaomi / Redmi / POCO | [Xiaomi's FAQ](https://www.mi.com/global/support/faq/details/KA-07238/) describes account/device pairing, eligibility and the Xiaomi unlock tool. Policies vary with device, region and OS; no textual key format is presumed and no account flow is automated here. |
| Nothing Phone (1), A063 (`Spacewar`) | [LineageOS device guide](https://lineageos.github.io/lineage_wiki/devices/Spacewar/install/) documents `fastboot flashing unlock` without a code for this model. No generalization to later Nothing devices. |
| HTC | Consult the exact model in [HTCdev's supported-device selector](https://www.htcdev.com/bootloader). HTCdev currently excludes models released after June 2018 and notes carrier restrictions even within its supported list. No text mask or binary token processing is implemented. |
| LG G4 International, H815 | [LineageOS H815 guide](https://lineageos.github.io/lineage_wiki/devices/h815/install/) states that an official unlocking method is unavailable. No inferred text mask; availability for other LG models is not established by this guide. |
