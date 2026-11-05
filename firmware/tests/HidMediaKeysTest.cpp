#include "../boards/175/MotoNav/HidMediaKeys.h"
#include <cassert>
#include <cstdio>
using namespace HidMediaKeys;
int main() {
  int checks = 0;
  auto check = [&](bool value) { assert(value); ++checks; };
  check(usageForButton(0) == 0xB6 && usageForButton(1) == 0xCD && usageForButton(2) == 0xB5);
  check(usageForButton(-1) == 0 && usageForButton(3) == 0);
  uint8_t bytes[2]; encode(PLAY_PAUSE, bytes);
  check(bytes[0] == 0xCD && bytes[1] == 0);
  encode(0, bytes); check(bytes[0] == 0 && bytes[1] == 0);
  // Decode HID short items and check the report is one 16-bit Consumer input.
  int page = 0, reportId = 0, reportBits = 0, reportCount = 0, inputBits = 0, collections = 0;
  bool keyboard = false;
  for (size_t i = 0; i < sizeof(REPORT_MAP); ) {
    uint8_t prefix = REPORT_MAP[i++];
    size_t length = prefix & 3; if (length == 3) length = 4;
    check(i + length <= sizeof(REPORT_MAP));
    uint32_t value = 0; for (size_t k = 0; k < length; ++k) value |= uint32_t(REPORT_MAP[i++]) << (8*k);
    uint8_t tag = prefix & 0xFC;
    if (tag == 0x04) { page = value; keyboard |= page == 7; }
    if (tag == 0x84) reportId = value;
    if (tag == 0x74) reportBits = value;
    if (tag == 0x94) reportCount = value;
    if (tag == 0x80) { check(page == 0x0C); inputBits += reportBits * reportCount; }
    if (tag == 0xA0) ++collections;
    if (tag == 0xC0) --collections;
  }
  check(!keyboard && reportId == REPORT_ID && inputBits == 16 && collections == 0);
  Pulses pulses; Pulses::Report r;
  check(!pulses.poll(0, r));
  check(!pulses.enqueue(-1));
  check(pulses.enqueue(1) && pulses.enqueue(2));
  check(pulses.poll(100, r) && r.usage == PLAY_PAUSE && !r.release);
  pulses.submitted(r, 100, true);
  check(!pulses.poll(159, r));
  check(pulses.poll(160, r) && r.usage == 0 && r.release);
  pulses.submitted(r, 160, true);
  check(!pulses.poll(199, r));
  check(pulses.poll(200, r) && r.usage == NEXT && !r.release);
  pulses.submitted(r, 200, true);
  check(pulses.poll(260, r) && r.release);
  pulses.submitted(r, 260, true);
  check(!pulses.poll(500, r));
  pulses.reset(); check(pulses.enqueue(0));
  check(pulses.poll(0, r) && r.usage == PREVIOUS);
  pulses.submitted(r, 0, false); // uncertain press: do not replay it
  check(pulses.poll(0, r) && r.release);
  pulses.submitted(r, 0, false);
  check(!pulses.poll(49, r));
  check(pulses.poll(50, r) && r.release && r.usage == 0);
  pulses.submitted(r, 50, true);
  check(!pulses.poll(1000, r));
  pulses.reset();
  for (size_t i = 0; i < Pulses::CAPACITY; ++i) check(pulses.enqueue(2));
  check(!pulses.enqueue(1));
  pulses.cancelQueued(); check(!pulses.poll(0, r));
  check(pulses.enqueue(1)); pulses.poll(0, r); pulses.submitted(r, 0, true);
  pulses.cancelQueued(); check(pulses.poll(60, r) && r.release); // changing mode still releases
  pulses.reset(); check(!pulses.poll(100, r)); // disconnect discards stale keys
  check(pulses.enqueue(1)); pulses.poll(0xFFFFFFF0u, r); pulses.submitted(r, 0xFFFFFFF0u, true);
  check(!pulses.poll(43, r));
  check(pulses.poll(44, r) && r.release); // millis wraps without a stuck key
  printf("HID media reports: %d checks passed\n", checks);
}
