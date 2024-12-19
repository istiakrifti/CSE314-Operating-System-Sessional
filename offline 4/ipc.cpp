#include <iostream>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <semaphore.h>
#include <vector>
#include <chrono>
#include <random>

using namespace std;
using namespace chrono;

mutex printMutex;
mutex photoBoothMutex;
condition_variable premiumVisitorCV;
condition_variable standardVisitorCV;
int totalVisitorsInBooth = 0;
int premiumVisitorsWaiting = 0;

mutex stepMutex[3];
sem_t gallery1Semaphore;
sem_t corridorDESemaphore;

default_random_engine generator;
double lambda = 2.0;
poisson_distribution<int> poissonDist(lambda);

void printStatus(int visitorId, const string &status, int timestamp) {
    lock_guard<mutex> lock(printMutex);
    cout << "Visitor " << visitorId << " " << status << " at timestamp " << timestamp << endl;
}

steady_clock::time_point startTime = steady_clock::now();

void photo_booth(int visitor_id, bool is_premium, int y, int z) {
    this_thread::sleep_for(milliseconds(y));
    {
        lock_guard<mutex> guard(photoBoothMutex);
        int timestamp = duration_cast<milliseconds>(steady_clock::now() - startTime).count();
        printStatus(visitor_id, "is about to enter the photo booth", timestamp);

        if (is_premium) {
            premiumVisitorsWaiting++;
        }
    }
    // this_thread::sleep_for(milliseconds(5));
    unique_lock<mutex> lock(photoBoothMutex);

    if (is_premium) {
        premiumVisitorCV.wait(lock, [] { return totalVisitorsInBooth == 0; });

        totalVisitorsInBooth++;
        premiumVisitorsWaiting--;

        int timestamp = duration_cast<milliseconds>(steady_clock::now() - startTime).count();
        printStatus(visitor_id, "is inside the photo booth", timestamp);

        lock.unlock();
        this_thread::sleep_for(milliseconds(z));
        lock.lock();

        totalVisitorsInBooth--;
        if (premiumVisitorsWaiting > 0) {
            premiumVisitorCV.notify_one();
        } else {
            standardVisitorCV.notify_all();
        }
    } else {
        standardVisitorCV.wait(lock, [] { return premiumVisitorsWaiting == 0; });

        totalVisitorsInBooth++;

        int timestamp = duration_cast<milliseconds>(steady_clock::now() - startTime).count();
        printStatus(visitor_id, "is inside the photo booth", timestamp);

        lock.unlock();
        this_thread::sleep_for(milliseconds(z));
        lock.lock();

        totalVisitorsInBooth--;
        if (totalVisitorsInBooth == 0 && premiumVisitorsWaiting > 0) {
            premiumVisitorCV.notify_one();
        } else {
            standardVisitorCV.notify_all();
        }
    }

    // int exitTimestamp = duration_cast<milliseconds>(steady_clock::now() - startTime).count();
    // printStatus(visitor_id, "is exiting Gallery 2", exitTimestamp);
}

void visitor(int id, int w, int x, int y, int z) {
    bool is_premium = id >= 2001;
    int initialDelay = poissonDist(generator);
    this_thread::sleep_for(milliseconds(initialDelay));

    int timestamp = duration_cast<milliseconds>(steady_clock::now() - startTime).count();
    printStatus(id, "has arrived at A", timestamp);

    this_thread::sleep_for(milliseconds(w));
    timestamp = duration_cast<milliseconds>(steady_clock::now() - startTime).count();
    printStatus(id, "has arrived at B", timestamp);

    unique_lock<mutex> step1Lock(stepMutex[0]);
    timestamp = duration_cast<milliseconds>(steady_clock::now() - startTime).count();
    printStatus(id, "is at step 1", timestamp);

    this_thread::sleep_for(milliseconds(1));
    unique_lock<mutex> step2Lock(stepMutex[1]);
    step1Lock.unlock();
    timestamp = duration_cast<milliseconds>(steady_clock::now() - startTime).count();
    printStatus(id, "is at step 2", timestamp);

    this_thread::sleep_for(milliseconds(1));
    unique_lock<mutex> step3Lock(stepMutex[2]);
    step2Lock.unlock();
    timestamp = duration_cast<milliseconds>(steady_clock::now() - startTime).count();
    printStatus(id, "is at step 3", timestamp);

    this_thread::sleep_for(milliseconds(1));
    // step3Lock.unlock();
    
    sem_wait(&gallery1Semaphore);
    step3Lock.unlock();
    timestamp = duration_cast<milliseconds>(steady_clock::now() - startTime).count();
    printStatus(id, "is at C (entered Gallery 1)", timestamp);

    this_thread::sleep_for(milliseconds(x));
    timestamp = duration_cast<milliseconds>(steady_clock::now() - startTime).count();
    printStatus(id, "is at D (exiting Gallery 1)", timestamp);

    sem_wait(&corridorDESemaphore);
    // timestamp = duration_cast<milliseconds>(steady_clock::now() - startTime).count();
    // printStatus(id, "is in Corridor DE", timestamp);

    this_thread::sleep_for(milliseconds(3));
    sem_post(&corridorDESemaphore);

    timestamp = duration_cast<milliseconds>(steady_clock::now() - startTime).count();
    printStatus(id, "is at E (entered Gallery 2)", timestamp);

    photo_booth(id, is_premium, y, z);

    sem_post(&gallery1Semaphore);
}

int main(int argc, char *argv[]) {
    if (argc != 7) {
        cerr << "Usage: " << argv[0] << " <N> <M> <w> <x> <y> <z>" << endl;
        return 1;
    }

    int N = stoi(argv[1]);
    int M = stoi(argv[2]);
    int w = stoi(argv[3]);
    int x = stoi(argv[4]);
    int y = stoi(argv[5]);
    int z = stoi(argv[6]);

    sem_init(&gallery1Semaphore, 0, 5);
    sem_init(&corridorDESemaphore, 0, 3);

    vector<thread> visitors;
    for (int i = 0; i < N; ++i) {
        visitors.push_back(thread(visitor, 1001 + i, w, x, y, z));
    }
    for (int i = 0; i < M; ++i) {
        visitors.push_back(thread(visitor, 2001 + i, w, x, y, z));
    }

    for (auto &v : visitors) {
        v.join();
    }

    sem_destroy(&gallery1Semaphore);
    sem_destroy(&corridorDESemaphore);

    return 0;
}
