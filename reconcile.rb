# Directions
# Download ynab data and Capital One Data
# run dos2unix on capital one data
# set file locations and earliest date
# run the file and check unmatched transactions

require "pry"
require "pry-byebug"
require "csv"
require "active_support/core_ext"

ynab_data_file = "data/ynab_data.csv"
bank_data_file = "data/AmazonTransaction.csv"

class Reconciler
  EARLIEST_DATE = Date.new(2020, 12, 15)

  attr_accessor :ynab_data,
    :bank_data,
    :matches,
    :ynab_multimatched,
    :ynab_unmatched,
    :bank_unmatched

  def initialize(ynab_data_file, bank_data_file)
    # @bank_data = load_capital_one_data(bank_data_file)
    # @bank_data = load_chase_data(bank_data_file)
    @bank_data = load_amazon_card_data(bank_data_file)
    @bank_data.reject! { |r| r[:date] < EARLIEST_DATE }
    @ynab_data = load_ynab_data(ynab_data_file)
    @matches = {}
    @ynab_multimatched = []
    @ynab_unmatched = @ynab_data.dup
    @bank_unmatched = @bank_data.dup
  end

  def load_ynab_data(ynab_data_file)
    data = CSV.foreach(ynab_data_file, headers: true, header_converters: :symbol)
      .select { |row| row[:account] == "Amazon Prime Store Card" }
      .map { |row|
        row.to_hash.except(:flag, :category_groupcategory).tap do |h|
          h[:inflow] = str_to_float(row[:inflow])
          h[:outflow] = str_to_float(row[:outflow])
          h[:amount] = if h[:inflow] == 0
            h[:outflow] * -1
          else
            h[:inflow]
          end
          h[:date] = Date.parse(h[:date])
        end
      }
      .reject { |h| h[:date] < EARLIEST_DATE || h[:cleared] == "Uncleared" }

    ynab_combine_splits(data)
  end

  def ynab_combine_splits(data)
    result = []
    current_split = nil
    split_curr = 0
    split_size = 0
    data.each do |h|
      if h[:memo].start_with? "Split"
        num, size = parse_split_str(h[:memo])
        if current_split.nil?
          split_curr = num
          split_size = size
          current_split = h
        else
          unless split_size == size && split_curr+1 == num
            binding.pry
            raise "Invalid split!"
          end
          split_curr = num
          current_split[:amount] += h[:amount]
          current_split[:inflow] += h[:inflow]
          current_split[:outflow] += h[:outflow]
          if num == split_size
            result << current_split if current_split[:amount] != 0
            current_split = nil
          end
        end
      else
        unless current_split.nil?
          result << current_split if current_split[:amount] != 0
          current_split = nil
        end
        result << h
      end
    end
    result << current_split unless current_split.nil?
    result
  end

  def parse_split_str(str)
    res = str.match(%r{Split \((\d)/(\d)\)})
    [res[1].to_i, res[2].to_i]
  end

  def load_capital_one_data(capital_one_data_file)
    CSV.foreach(capital_one_data_file, headers: true, header_converters: :symbol)
      .map do |row|
        row.to_hash.except(:account_number, :balance, :transaction_amount, :transaction_date).tap do |h|
          h[:amount] = row[:transaction_amount].to_f
          d = row[:transaction_date].split("/").map(&:to_i)
          h[:date] = Date.new(d[2] + 2000, d[0], d[1])
        end
      end
  end

  def load_chase_data(chase_data_file)
    CSV.foreach(chase_data_file, headers: true, header_converters: :symbol)
      .map do |row|
        row.to_hash.except(:amount, :transaction_date, :category, :post_date).tap do |h|
          h[:amount] = row[:amount].to_f
          d = row[:transaction_date].split("/").map(&:to_i)
          h[:date] = Date.new(d[2], d[0], d[1])
        end
      end
  end

  def load_amazon_card_data(amazon_card_data_file)
    CSV.foreach(amazon_card_data_file, headers: true, header_converters: :symbol)
      .map do |row|
        row.to_hash.except(:amount, :transaction_date, :reference_number).tap do |h|
          h[:amount] = row[:amount].to_f
          d = row[:transaction_date].split("/").map(&:to_i)
          h[:date] = Date.new(d[2], d[0], d[1])
        end
      end
  end

  def str_to_float(str)
    str[1..-1].to_f
  end

  def run_matches(&block)
    ynab_multimatched.clear
    ynab_unmatched.each do |y|
      potential = bank_unmatched.select { |c| yield(y, c) }

      case potential.size
      when 1
        matches[y] = match = potential.first
        bank_unmatched.delete(match)
      when 0
        nil
        # do nothing
      else
        # binding.pry
        ynab_multimatched << y
      end
    end

    if (dup_count = matches.values.count - matches.values.uniq.count) > 0
      raise "dup count is #{dup_count}!!!"
    end

    @ynab_unmatched = ynab_data - matches.keys

    nil
  end

  def n_day_match?(n, y, c)
    y[:amount].round(2) == c[:amount].round(2) &&
      (y[:date] - c[:date]).abs <= n
  end

  def run_n_day_matches(n)

    run_matches { |y, c| n_day_match?(n, y, c) }
  end

  def toss_reconciled
    @ynab_unmatched.reject! { |h| h[:cleared] == "Reconciled" }
  end
end

reconciler = Reconciler.new(ynab_data_file, bank_data_file)

def summary(i, reconciler)
  puts <<~STR
    Summary after #{i} day match
    Matched:         #{reconciler.matches.size}
    Unmatched YNAB:  #{reconciler.ynab_unmatched.size}
    Unmatched Bank:  #{reconciler.bank_unmatched.size}
    YNAB multimatch: #{reconciler.ynab_multimatched.size}
  STR
end

summary(0, reconciler)
10.times do |i|
  reconciler.run_n_day_matches(i)
  summary(i, reconciler)
end
# reconciler.toss_reconciled

binding.pry

reconciler.inspect
