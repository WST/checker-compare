#!/usr/bin/env ruby

# Начало работы скрипта
start_time = Time.now

require 'nokogiri'
require 'http'
require 'thread'

# Путь к файлу XML-дампа
DUMP_XML = '/home/ilya/projects/roskombox/cache/dump.xml'

# Мьютексы
$in_mutex = Mutex.new
$out_mutex = Mutex.new

# Прогресс
$progress = 0

class RoskomWorker
	def initialize(in_list, out_list, instance)
		@instance = instance
		@in_list = in_list
		@out_list = out_list
		@total = in_list.length
	end

	def select_unprocessed()
		$in_mutex.synchronize {
			return @in_list.pop
		}
	end

	def report_progress(item)
		$out_mutex.synchronize {
			$progress += 1
			printf "(%d of %d) [%s] %s\n", $progress, @total, item[1], item[0]
		}
	end

	def process_item(item)
		begin
			response = HTTP.get(item[0])
			response_text = response.to_s
			if (response.code == 302) and (response.headers['Location'] == 'http://mkpnet.ru/blocked.html') then
				item[1] = 'blocked'
			else
				item[1] = 'available'
			end
		rescue Exception => msg
			item[1] = 'failure'
		end

		self.report_progress(item)
	end

	def start()
		while true do
			item = self.select_unprocessed()
			if item == nil then
				break
			else
				self.process_item(item)
			end
		end
	end
end

class RoskomParser
	def initialize(filename)
		@filename = filename
		@in_list = []
	end

	def parse()
		tree = File.open(@filename) { |file| Nokogiri::XML(file) }

		records = tree.xpath('//content')
		records.each do |i|
			urls = i.xpath('url')
			urls.each do |u|
				@in_list.push([u.inner_text, 'unknown'])
			end
		end

		return @in_list
	end
end

parser = RoskomParser.new(DUMP_XML)
in_list = parser.parse()
out_list = []

workers = []
threads = []

(0..99).each do |i|
	workers << RoskomWorker.new(in_list, out_list, i)
end

workers.each do |worker|
	threads << Thread.new { Thread.stop; worker.start }
end

# Разветвляемся
threads.each { |thread| thread.run }

# Соединяемся
threads.each { |thread| thread.join }

# Завершение скрипта
end_time = Time.now
diff = end_time - start_time

printf("%.2f seconds\n", diff)
