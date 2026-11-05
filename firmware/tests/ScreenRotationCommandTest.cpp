#include "../boards/175/MotoNav/ScreenRotationCommand.h"
#include <cassert>
#include <iostream>
int main() {
  int checks = 0;
  auto check = [&](const char *text, int expected) {
    int degrees = -999; assert(ScreenRotationCommand::parse(text, degrees)); assert(degrees == expected); ++checks;
  };
  for (int quarter = 0; quarter < 4; ++quarter) {
    char command[24]; snprintf(command, sizeof(command), "#R,%d", quarter); check(command, quarter * 90);
  }
  // This is the exact wire format emitted by the installed iOS rotation dial.
  for (int angle = 0; angle < 360; ++angle) {
    char command[24]; snprintf(command, sizeof(command), "#R,%d,%d", ((angle + 45) / 90) & 3, angle); check(command, angle);
  }
  check("#R,0,37",37); check("#R,1,89",89); check("#R,0,359",359);
  check("#R,0,360",0); check("#R,0,-1",359); check("#R,0,721",1);
  check("#D37",37); check("#D-37",323); check("#D360",0); check("#D721",1);
  check("#R,1,2147483647",127); check("#R,1,-2147483648",232);
  for (auto malformed : {static_cast<const char *>(nullptr), "", "#R,", "#R,4", "#R,-1", "#R,0,", "#R,0,abc", "#R,0,37,", "#R,0,37junk", "#R,0,2147483648", "#R,0,-2147483649", "#D", "#Dabc", "#D37,", "#D 37", "#R,0, 37", "#HM,1", "R,100"}) {
    int degrees = 123; assert(!ScreenRotationCommand::parse(malformed, degrees)); assert(degrees == 123); ++checks;
  }
  std::cout << "Screen rotation command: " << checks << " checks passed\n";
}
