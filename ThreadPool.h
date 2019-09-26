#pragma once

#ifndef THREAD_POOL_H
#define THREAD_POOL_H

#include <mutex>
#include <condition_variable>
#include <thread>
#include <vector>
#include <queue>
#include <functional>

using namespace std;

class ThreadPool
{
public:
	explicit ThreadPool(size_t size = thread::hardware_concurrency()) {
		auto workThread = [this]()->void {
			while (true) {
				unique_lock<mutex> guard(m_mutex);
				if (!m_tasks.empty()) {
					auto task = std::move(m_tasks.front());
					m_tasks.pop();
					guard.unlock();
					task();
					guard.lock();
				}
				else if (m_bIsShutdown) {
					break;
				}
				else {
					m_condition.wait(guard);
				}
			}
		};
		for (size_t i = 0; i < size; ++i) {
			m_threads.emplace_back(workThread);
		}
	}
	ThreadPool(const ThreadPool &) = delete;
	ThreadPool & operator=(const ThreadPool &) = delete;
	~ThreadPool() {
		unique_lock<mutex> guard(m_mutex);
		m_bIsShutdown = true;
		guard.unlock();
		m_condition.notify_all();
		for (auto iter = m_threads.begin(); iter != m_threads.end(); ++iter) {
			iter->join();
		}
	}

public:
	template <typename T>
	void execute(T &&task) {
		unique_lock<mutex> guard(m_mutex);
		m_tasks.emplace(std::forward<T>(task));
		guard.unlock();
		m_condition.notify_one();
	}

private:
	mutex m_mutex;
	condition_variable m_condition;
	queue<function<void()>> m_tasks;
	vector<thread> m_threads;
	bool m_bIsShutdown = false;
};

#endif // !THREAD_POOL_H