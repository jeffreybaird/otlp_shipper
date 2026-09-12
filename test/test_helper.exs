# Allow scheduling and initial HTTP pool setup on shared CI runners. Transport
# deadline tests still set and assert their own explicit export time budgets.
ExUnit.start(assert_receive_timeout: 1000)
