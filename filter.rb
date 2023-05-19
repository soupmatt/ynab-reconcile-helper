require "pry"
require "active_support/all"
require "csv"

DATE_UPPER_LIMIT = Date.today
DATE_LOWER_LIMIT = 30.days.ago.to_date

def filter_file(prefix)
  puts "filtering #{prefix}"
  input = CSV.open("data/#{prefix}_all.csv", "r", headers: true)
  output = CSV.open("data/#{prefix}_filtered.csv", "w", headers: input.headers)

  input.each do |row|
    date = Date.parse(row["Date"])
    if date >= DATE_LOWER_LIMIT && date <= DATE_UPPER_LIMIT
      output << row
    end
  end
ensure
  input.close unless input.nil?
  output.close unless output.nil?
end

filter_file("register")
