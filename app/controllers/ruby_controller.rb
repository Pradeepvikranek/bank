1. Adjust for Ruby 3.2+ (string uses new timestamp)
ruby
Copy
Edit
DepositMetadata.timestamp = deposit_timestamp
DepositReference.reference = "Ref based on timestamp: #{DepositMetadata.timestamp.inspect}"
First, you assign the new timestamp to DepositMetadata.timestamp.

Then you build deposit_ref_string based on the new timestamp (just assigned).

So deposit_ref_string reflects the latest timestamp.

2. Keep old behavior (string uses old timestamp)
ruby
Copy
Edit
old_timestamp = DepositMetadata.timestamp

deposit_ref_string = "Ref based on timestamp: #{old_timestamp.inspect}"

DepositMetadata.timestamp = deposit_timestamp
DepositReference.reference = deposit_ref_string

| Ruby version | Your current code behavior                                         | Adjust needed?                | Suggested fix                                                 |
| ------------ | ------------------------------------------------------------------ | ----------------------------- | ------------------------------------------------------------- |
| 3.1          | `deposit_ref_string` uses old timestamp (`nil`)                    | No                            | No change needed                                              |
| 3.2          | `deposit_ref_string` uses new timestamp (due to eval order change) | Yes, if you want old behavior | Separate assignments, cache old value before building string. |
