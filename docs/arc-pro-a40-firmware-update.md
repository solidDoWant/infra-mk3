# Updating the firmware for Arc A40 Pro GPUs

1. Create a privileged pod on the targeted node

    ```yaml
    ---
    apiVersion: v1
    kind: Pod
    metadata:
    name: firmware-update
    spec:
    hostNetwork: true
    hostPID: true
    containers:
        - name: admin
          image: ubuntu:22.04
          command:
            - sleep
            - "999999999999"
          securityContext:
              allowPrivilegeEscalation: true
              capabilities:
              add:
                - SYS_ADMIN
              privileged: true
          volumeMounts:
            - name: sys
              mountPath: /sys
            - name: dev
              mountPath: /dev
    volumes:
      - name: sys
        hostPath:
          path: /sys
      - name: dev
        hostPath:
          path: /dev
    restartPolicy: Always
    ```
2. Enter the pod

    ```shell
    kubectl exec -it pods/firmware-update -- bash
    ```

3. Build the firmware update tool

    ```shell
    apt update
    apt install -y cmake g++ git ninja-build libudev-dev ca-certificates curl unrar
    cd /tmp
    git clone --branch V0.9.5 https://github.com/intel/igsc.git
    cd igsc
    cmake -G Ninja -S . -B builddir
    ninja -v -C builddir
    ```

4. Download the [latest Arc Pro graphics drivers from Intel](https://www.intel.com/content/www/us/en/download/741626/intel-arc-pro-graphics-windows.html)

    ```shell
    mkdir /tmp/firmware-extract
    pushd /tmp/firmware-extract
    curl -fsSL -o gfx.exe  https://downloadmirror.intel.com/850602/gfx_win_101.6637.exe
    ```

5. Extract the firmware files

    ```shell
    unrar -l gfx.exe
    # Note: firmware for HDMI PCon is not supported by igsc: https://github.com/intel/igsc/issues/13#issuecomment-2558920726
    unrar e gfx.exe \
        Graphics/ifwi/acm/opromcode/dg2_c_oprom.rom \
        Graphics/ifwi/acm/opromdata/dg2_d_intel_a40_oprom-data.rom \
        Graphics/ifwi/acm/fwcode/dg2_gfx_fwupdate_SOC2.bin \
        Graphics/ifwi/acm/fwdata/dg2_intel_a40_config-data.bin
    ```

6. Flash the firmware

    ```shell
    popd
    # Firmware
    ./builddir/src/igsc fw update --device /dev/mei2 --image /tmp/firmware-extract/dg2_gfx_fwupdate_SOC2.bin
    # OPROM data
    ./builddir/src/igsc oprom-data update --device /dev/mei2 --image /tmp/firmware-extract/dg2_d_intel_a40_oprom-data.rom
    # OPROM code
    ./builddir/src/igsc oprom-code update --device /dev/mei2 --image /tmp/firmware-extract/dg2_c_oprom.rom
    # Firmware data
    ./builddir/src/igsc fw-data update --device /dev/mei2 --image /tmp/firmware-extract/dg2_intel_a40_config-data.bin
    ```

7. Cleanup

    ```shell
    kubectl delete pod firmware-update
    ```

---

* [Flashing guide](https://www.techpowerup.com/forums/threads/guide-flashing-intel-arc-gpus.311964/)
* [A40 flashing discussion](https://www.techpowerup.com/forums/threads/intel-pro-arc-a40.337680/)
