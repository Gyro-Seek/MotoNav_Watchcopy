#include "../boards/175/MotoNav/AppleMediaCommands.h"
#include <cassert>
#include <iostream>
int main() {
  int checks = 0; auto check = [&](bool p) { assert(p); ++checks; };
  using namespace AppleMediaCommands; Queue q; uint8_t c;
  check(forButton(0) == 4); check(forButton(1) == 2); check(forButton(2) == 3); check(forButton(-1) == -1); check(forButton(3) == -1);
  check(!q.enqueue(-1)); check(!q.enqueue(3));
  check(q.enqueue(0)); check(q.enqueue(1)); check(q.enqueue(2));
  check(q.take(c) && c == 4); check(q.take(c) && c == 2); check(q.take(c) && c == 3); check(!q.take(c));
  const uint8_t onlyNext[] = {3,255}; q.supported(onlyNext,2);
  check(!q.supports(0)); check(!q.supports(1)); check(q.supports(2));
  check(!q.enqueue(1));
  for (int i = 0; i < 4; ++i) check(q.enqueue(2));
  check(!q.enqueue(2)); q.cancel(); check(!q.take(c));
  q.reset(); check(q.enqueue(1)); q.supported(onlyNext,2); check(!q.take(c));
  q.reset(); check(q.enqueue(1)); q.reset(); check(!q.take(c));
  q.supported(nullptr,0); check(!q.supports(0)); check(!q.supports(1)); check(!q.supports(2));
  std::cout << "AMS command queue: " << checks << " checks passed\n";
}
