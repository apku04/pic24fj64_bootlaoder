#!/usr/bin/env python3
"""
PIC24 USB Bootloader Upload Tool

Uploads Intel HEX firmware files to PIC24 via USB CDC bootloader.

Usage:
    python upload_firmware.py <hexfile> [--port COM3] [--no-verify] [--no-jump] [--reset]

Protocol:
    V - Get bootloader version
    E - Erase application area
    : - Intel HEX record (data)
    C - Verify/complete
    J - Jump to application
    X - Reset device
"""

import argparse
import serial
import serial.tools.list_ports
import time
import sys
import re
import csv
from datetime import datetime
from pathlib import Path


class BootloaderUploader:
    """USB CDC Bootloader communication class."""
    
    def __init__(self, port: str = None, baudrate: int = 115200, timeout: float = 5.0):
        self.port = port
        self.baudrate = baudrate
        self.timeout = timeout
        self.serial = None
        
    def find_bootloader_port(self) -> str:
        """Auto-detect the bootloader COM port."""
        ports = serial.tools.list_ports.comports()
        
        for port in ports:
            # Look for Microchip USB CDC devices (VID 0x04D8)
            vid_str = f"{port.vid:04X}" if port.vid else ""
            if "04D8" in vid_str or \
               "Microchip" in (port.manufacturer or "") or \
               "CDC" in (port.description or "").upper():
                print(f"Found bootloader at {port.device}: {port.description}")
                return port.device
        
        # List all available ports
        print("Available COM ports:")
        for port in ports:
            vid_str = f"{port.vid:04X}" if port.vid else "N/A"
            print(f"  {port.device}: {port.description} (VID:{vid_str})")
        
        return None
    
    def connect(self) -> bool:
        """Connect to the bootloader."""
        if self.port is None:
            self.port = self.find_bootloader_port()
            if self.port is None:
                print("ERROR: No bootloader found. Is the device connected?")
                return False
        
        try:
            self.serial = serial.Serial(
                port=self.port,
                baudrate=self.baudrate,
                timeout=self.timeout,
                write_timeout=self.timeout
            )
            time.sleep(0.5)  # Wait for connection to stabilize
            self.serial.reset_input_buffer()
            return True
        except serial.SerialException as e:
            print(f"ERROR: Cannot open {self.port}: {e}")
            return False
    
    def disconnect(self):
        """Disconnect from bootloader."""
        if self.serial and self.serial.is_open:
            self.serial.close()
    
    def send_command(self, cmd: str, wait_response: bool = True) -> tuple[bool, str]:
        """Send a command and optionally wait for response."""
        try:
            self.serial.write((cmd + "\r\n").encode('ascii'))
            self.serial.flush()
            
            if not wait_response:
                return True, ""
            
            # Read response with timeout tracking
            import time as t
            start = t.time()
            response = self.serial.readline().decode('ascii', errors='ignore').strip()
            elapsed = t.time() - start
            
            if elapsed > 0.5:
                print(f"\n  [Slow response: {elapsed:.2f}s]", end="")
            
            if response.startswith('+'):
                return True, response[1:]
            elif response.startswith('-'):
                return False, response[1:]
            elif response.startswith('?'):
                return False, "Unknown command"
            else:
                return True, response  # Version string or other data
                
        except serial.SerialException as e:
            return False, str(e)
    
    def get_version(self) -> str:
        """Get bootloader version."""
        success, response = self.send_command('V')
        return response if success else None
    
    def erase_application(self) -> bool:
        """Erase the application flash area."""
        print("Erasing application area...", end=" ", flush=True)
        # Erase can take a while, increase timeout temporarily
        old_timeout = self.serial.timeout
        self.serial.timeout = 10.0
        
        success, response = self.send_command('E')
        
        self.serial.timeout = old_timeout
        
        if success:
            print("OK")
        else:
            print(f"FAILED: {response}")
        return success
    
    def send_hex_record(self, record: str) -> bool:
        """Send a single Intel HEX record."""
        success, response = self.send_command(record)
        return success
    
    def verify_complete(self) -> tuple[bool, str]:
        """Signal completion and get verification result."""
        return self.send_command('C')
    
    def jump_to_app(self) -> bool:
        """Command bootloader to jump to application."""
        print("Jumping to application...")
        success, response = self.send_command('J', wait_response=True)
        if response:
            print(f"  Bootloader: {response}")
        return success
    
    def reset_device(self) -> bool:
        """Reset the device."""
        print("Resetting device...")
        success, _ = self.send_command('X', wait_response=False)
        return success


def parse_hex_file(filepath: Path) -> list[str]:
    """Parse an Intel HEX file and return list of records."""
    records = []
    
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith(':'):
                records.append(line)
    
    return records


def upload_firmware(hexfile: Path, port: str = None, verify: bool = True, 
                   jump_to_app: bool = True) -> bool:
    """Upload firmware to the bootloader."""
    
    print(f"\n{'='*50}")
    print(" PIC24 Bootloader Firmware Upload")
    print(f"{'='*50}")
    print(f"File: {hexfile}")
    
    # Parse HEX file
    if not hexfile.exists():
        print(f"ERROR: File not found: {hexfile}")
        return False
    
    records = parse_hex_file(hexfile)
    if not records:
        print("ERROR: No valid records in HEX file")
        return False
    
    print(f"HEX records: {len(records)}")
    
    # Connect to bootloader
    uploader = BootloaderUploader(port=port)
    
    if not uploader.connect():
        return False
    
    try:
        # Get version
        version = uploader.get_version()
        if version:
            print(f"Bootloader: {version}")
        else:
            print("WARNING: Could not get bootloader version")
        
        # Erase application area
        if not uploader.erase_application():
            print("ERROR: Erase failed")
            return False
        
        # Send HEX records
        print(f"\nUploading {len(records)} records...")
        
        errors = 0
        bytes_sent = 0
        for i, record in enumerate(records):
            # Parse record to show address info
            if record.startswith(':') and len(record) >= 11:
                rec_type = int(record[7:9], 16)
                rec_addr = int(record[3:7], 16)
                rec_len = int(record[1:3], 16)
                bytes_sent += rec_len
            
            if not uploader.send_hex_record(record):
                errors += 1
                print(f"\n  ERROR on record {i}: {record[:30]}...")
                if errors > 5:
                    print(f"\nERROR: Too many errors, aborting")
                    return False
            
            # Progress indicator every 100 records or on specific types
            if (i + 1) % 100 == 0 or i == len(records) - 1:
                pct = (i + 1) * 100 // len(records)
                print(f"\r  Progress: {i+1}/{len(records)} ({pct}%) - {bytes_sent} bytes", end="", flush=True)
        
        print()  # Newline after progress
        
        # Verify
        if verify:
            print("Verifying...", end=" ", flush=True)
            success, result = uploader.verify_complete()
            if success:
                print(f"OK - {result}")
            else:
                print(f"FAILED: {result}")
                return False
        
        # Jump to application
        if jump_to_app:
            time.sleep(0.2)
            uploader.jump_to_app()
        
        print(f"\n{'='*50}")
        print(" UPLOAD SUCCESSFUL")
        print(f"{'='*50}\n")
        return True
        
    except Exception as e:
        print(f"\nERROR: {e}")
        return False
    
    finally:
        uploader.disconnect()


def _parse_version_fields(version_line: str) -> dict:
    """Extract numeric fields from a single-line bootloader version response."""
    if not version_line:
        return {}
    fields: dict[str, object] = {}

    # Examples:
    #   BLv1.2 SJ=49159 JRC=2 CC=27423
    #   BLv1.2 SJ=... JRC=... CC=... RC=00A4
    patterns = {
        "sj": r"\bSJ=(\d+)",
        "jrc": r"\bJRC=(\d+)",
        "cc": r"\bCC=(\d+)",
        "rc": r"\bRC=([0-9A-Fa-f]+)",
    }

    for key, pattern in patterns.items():
        match = re.search(pattern, version_line)
        if not match:
            continue
        value_str = match.group(1)
        if key == "rc":
            try:
                fields[key] = int(value_str, 16)
            except ValueError:
                fields[key] = value_str
        else:
            fields[key] = int(value_str)

    return fields


def _get_version_once(port: str | None) -> str | None:
    uploader = BootloaderUploader(port=port)
    if not uploader.connect():
        return None
    try:
        return uploader.get_version()
    finally:
        uploader.disconnect()


def get_version_with_retry(port: str | None, timeout_s: float = 3.0, poll_s: float = 0.3) -> str | None:
    """Try to connect+read version for up to timeout_s. Returns None if unreachable."""
    deadline = time.time() + timeout_s
    last = None
    while time.time() < deadline:
        last = _get_version_once(port)
        if last:
            return last
        time.sleep(poll_s)
    return last


def ralph_loop(
    *,
    port: str | None,
    hexfile: Path | None,
    iterations: int,
    verify: bool,
    upload_mode: str,
    after_jump_delay_s: float,
    between_iter_delay_s: float,
    csv_log: Path | None,
) -> int:
    """Rapid repeat loop: version -> optional upload -> jump -> version."""
    if iterations <= 0:
        raise ValueError("iterations must be > 0")

    records = None
    if hexfile is not None:
        if not hexfile.exists():
            print(f"ERROR: File not found: {hexfile}")
            return 1
        records = parse_hex_file(hexfile)
        if not records:
            print("ERROR: No valid records in HEX file")
            return 1

    writer = None
    csv_file = None
    if csv_log is not None:
        csv_log.parent.mkdir(parents=True, exist_ok=True)
        csv_file = open(csv_log, "a", newline="", encoding="utf-8")
        writer = csv.DictWriter(
            csv_file,
            fieldnames=[
                "ts",
                "iter",
                "pre_version",
                "post_version",
                "pre_sj",
                "post_sj",
                "pre_jrc",
                "post_jrc",
                "pre_rc",
                "post_rc",
                "note",
            ],
        )
        if csv_file.tell() == 0:
            writer.writeheader()

    exit_code = 0
    try:
        for i in range(1, iterations + 1):
            ts = datetime.now().isoformat(timespec="seconds")
            print(f"\n--- Ralph loop {i}/{iterations} ---")

            pre_version = get_version_with_retry(port, timeout_s=3.0)
            if pre_version:
                print(f"Pre:  {pre_version}")
            else:
                print("Pre:  (bootloader not reachable)")

            did_upload = False
            if records is not None and (upload_mode == "each" or (upload_mode == "once" and i == 1)):
                did_upload = True
                ok = upload_firmware(
                    hexfile=hexfile,
                    port=port,
                    verify=verify,
                    jump_to_app=True,
                )
                if not ok:
                    exit_code = 1
                    note = "upload_failed"
                    post_version = get_version_with_retry(port, timeout_s=3.0)
                    if writer:
                        pre_fields = _parse_version_fields(pre_version or "")
                        post_fields = _parse_version_fields(post_version or "")
                        writer.writerow(
                            {
                                "ts": ts,
                                "iter": i,
                                "pre_version": pre_version or "",
                                "post_version": post_version or "",
                                "pre_sj": pre_fields.get("sj", ""),
                                "post_sj": post_fields.get("sj", ""),
                                "pre_jrc": pre_fields.get("jrc", ""),
                                "post_jrc": post_fields.get("jrc", ""),
                                "pre_rc": pre_fields.get("rc", ""),
                                "post_rc": post_fields.get("rc", ""),
                                "note": note,
                            }
                        )
                    break
            else:
                # Jump-only iteration
                uploader = BootloaderUploader(port=port)
                if uploader.connect():
                    try:
                        uploader.jump_to_app()
                    finally:
                        uploader.disconnect()
                else:
                    print("Jump: (bootloader not reachable; skipping jump)")

            time.sleep(max(0.0, after_jump_delay_s))

            post_version = get_version_with_retry(port, timeout_s=2.0)
            note = ""
            if post_version:
                print(f"Post: {post_version}")
                # If post_version is readable, we are still in bootloader.
                note = "bootloader_returned"
            else:
                print("Post: (bootloader not reachable; likely app stayed running)")
                note = "bootloader_gone"

            if writer:
                pre_fields = _parse_version_fields(pre_version or "")
                post_fields = _parse_version_fields(post_version or "")
                if did_upload:
                    note = (note + ";uploaded").lstrip(";")
                writer.writerow(
                    {
                        "ts": ts,
                        "iter": i,
                        "pre_version": pre_version or "",
                        "post_version": post_version or "",
                        "pre_sj": pre_fields.get("sj", ""),
                        "post_sj": post_fields.get("sj", ""),
                        "pre_jrc": pre_fields.get("jrc", ""),
                        "post_jrc": post_fields.get("jrc", ""),
                        "pre_rc": pre_fields.get("rc", ""),
                        "post_rc": post_fields.get("rc", ""),
                        "note": note,
                    }
                )

            time.sleep(max(0.0, between_iter_delay_s))
    finally:
        if csv_file is not None:
            csv_file.close()

    return exit_code


def main():
    parser = argparse.ArgumentParser(
        description="Upload firmware to PIC24 USB Bootloader",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python upload_firmware.py firmware.hex
  python upload_firmware.py firmware.hex --port COM5
  python upload_firmware.py firmware.hex --no-jump

  # Control-only (no erase/upload):
  python upload_firmware.py --port COM5 --version-only
  python upload_firmware.py --port COM5 --jump-only
  python upload_firmware.py --port COM5 --reset-only
        """
    )

    parser.add_argument('hexfile', nargs='?', type=Path,
                        help='Intel HEX file to upload (omit when using --*-only commands)')
    parser.add_argument('--port', '-p', type=str, default=None,
                        help='COM port (auto-detect if not specified)')

    action_group = parser.add_mutually_exclusive_group()
    action_group.add_argument('--version-only', action='store_true',
                              help='Only query and print the bootloader version, then exit')
    action_group.add_argument('--jump-only', action='store_true',
                              help='Only command the bootloader to jump to the application, then exit')
    action_group.add_argument('--reset-only', action='store_true',
                              help='Only command the bootloader to reset the device, then exit')

    parser.add_argument('--no-verify', action='store_true',
                        help='Skip verification after upload')
    parser.add_argument('--no-jump', action='store_true',
                        help='Do not jump to application after upload')
    parser.add_argument('--reset', action='store_true',
                        help='Reset device instead of jumping to app (after upload)')

    # Rapid iteration mode
    parser.add_argument('--ralph-loop', type=int, default=0,
                        help='Run N rapid iterations: version -> (optional upload) -> jump -> version')
    parser.add_argument('--loop-upload', choices=['once', 'each'], default='once',
                        help='In --ralph-loop mode: upload once (first iter) or each iteration')
    parser.add_argument('--after-jump-delay', type=float, default=0.5,
                        help='Seconds to wait after jump before post-version probe')
    parser.add_argument('--between-iter-delay', type=float, default=0.5,
                        help='Seconds to wait between iterations')
    parser.add_argument('--log-csv', type=Path, default=None,
                        help='Optional CSV log file path for --ralph-loop results')

    args = parser.parse_args()

    if args.ralph_loop > 0 and (args.version_only or args.jump_only or args.reset_only):
        parser.error("--ralph-loop cannot be combined with --version-only/--jump-only/--reset-only")

    if args.ralph_loop > 0:
        # In loop mode, hexfile is optional (if omitted, this becomes a jump-only loop).
        exit_code = ralph_loop(
            port=args.port,
            hexfile=args.hexfile,
            iterations=args.ralph_loop,
            verify=not args.no_verify,
            upload_mode=args.loop_upload,
            after_jump_delay_s=args.after_jump_delay,
            between_iter_delay_s=args.between_iter_delay,
            csv_log=args.log_csv,
        )
        sys.exit(exit_code)

    # Control-only actions: no HEX required
    if args.version_only or args.jump_only or args.reset_only:
        uploader = BootloaderUploader(port=args.port)
        if not uploader.connect():
            sys.exit(1)
        try:
            if args.version_only:
                version = uploader.get_version()
                if version is None:
                    print("ERROR: Failed to read version")
                    sys.exit(1)
                print(version)
                sys.exit(0)

            if args.jump_only:
                if uploader.jump_to_app():
                    sys.exit(0)
                print("ERROR: Failed to send jump command")
                sys.exit(1)

            if args.reset_only:
                if uploader.reset_device():
                    sys.exit(0)
                print("ERROR: Failed to send reset command")
                sys.exit(1)
        finally:
            uploader.disconnect()

    # Normal upload path requires a HEX file
    if args.hexfile is None:
        parser.error("hexfile is required unless using --version-only/--jump-only/--reset-only")

    success = upload_firmware(
        hexfile=args.hexfile,
        port=args.port,
        verify=not args.no_verify,
        jump_to_app=not args.no_jump and not args.reset
    )

    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
