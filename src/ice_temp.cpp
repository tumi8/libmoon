#include <math.h>
#include <iostream>
#include <chrono>
#include <fstream>
#include <vector>

#include <rte_config.h>
#include <rte_ethdev.h>

#include "lifecycle.h"

struct time_values
{
	int64_t timestamp;
	float temperature;
};

extern "C" float ice_get_qsfp_temp(int port);

extern "C" void record_temperature(int port){
	std::vector<struct time_values> times;
	times.reserve(100000);

	while (is_running(0)) {
		times.push_back({std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::now().time_since_epoch()).count(), ice_get_qsfp_temp(port)});
		rte_delay_ms(1000);
	}

	{
        std::ofstream file;
        file.open(("temps_" + std::to_string(port) + ".csv").c_str(), std::ios::out | std::ios::trunc);

        for(const auto& point : times){
            file << std::fixed << point.timestamp << ","  << point.temperature << std::endl;
        }
    }
}
