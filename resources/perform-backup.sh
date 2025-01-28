#/bin/sh


# Set the has_failed variable to false. This will change if any of the subsequent database backups/uploads fail.
has_failed=false
backup_name=""


# Loop through all the defined databases, seperating by a ,
for CURRENT_DATABASE in ${TARGET_DATABASE_NAMES//,/ }
do

    # Perform the database backup. Put the output to a variable. If successful upload the backup to S3, if unsuccessful print an entry to the console and the log, and set has_failed to true.
    if sqloutput=$(mysqldump -u $TARGET_DATABASE_USER -h $TARGET_DATABASE_HOST -p$TARGET_DATABASE_PASSWORD -P $TARGET_DATABASE_PORT $CURRENT_DATABASE 2>&1 > /tmp/$CURRENT_DATABASE.sql)
    then

        echo -e "Database backup successfully completed for $CURRENT_DATABASE at $(date +'%d-%m-%Y %H:%M:%S')."

         FILENAME=$CURRENT_DATABASE_$(date +"%Y-%m-%d_%H-%M-%S")

        if [ "$USE_COMPRESSION" = true ]
        then
          tar -czvf /tmp/$CURRENT_DATABASE.tar.gz /tmp/$CURRENT_DATABASE.sql
          FILENAME=$FILENAME.tar.gz
          awsoutput=$(aws s3 cp /tmp/$CURRENT_DATABASE.tar.gz s3://$AWS_BUCKET_BACKUP_PATH/$FILENAME --endpoint-url $AWS_BUCKET_URI 2>&1)
        else
          FILENAME=$FILENAME.sql
          awsoutput=$(aws s3 cp /tmp/$CURRENT_DATABASE.sql s3://$AWS_BUCKET_BACKUP_PATH/$FILENAME --endpoint-url $AWS_BUCKET_URI 2>&1)
        fi
        # Perform the upload to S3. Put the output to a variable. If successful, print an entry to the console and the log. If unsuccessful, set has_failed to true and print an entry to the console and the log
        if [ "$awsoutput" = true ]
        then
            echo -e "Database backup successfully uploaded for $CURRENT_DATABASE at $(date +'%d-%m-%Y %H:%M:%S')."
        else
            echo -e "Database backup failed to upload for $CURRENT_DATABASE at $(date +'%d-%m-%Y %H:%M:%S'). Error: $awsoutput" | tee -a /tmp/kubernetes-s3-mysql-backup.log
            has_failed=true
        fi

    else
        echo -e "Database backup FAILED for $CURRENT_DATABASE at $(date +'%d-%m-%Y %H:%M:%S'). Error: $sqloutput" | tee -a /tmp/kubernetes-s3-mysql-backup.log
        has_failed=true
    fi

done



# Check if any of the backups have failed. If so, exit with a status of 1. Otherwise exit cleanly with a status of 0.
if [ "$has_failed" = true ]
then

    # If Slack alerts are enabled, send a notification alongside a log of what failed
    if [ "$NOTIFY_ENABLED" = true ]
    then
        # Put the contents of the database backup logs into a variable
        logcontents=`cat /tmp/kubernetes-s3-mysql-backup.log`

        # Send Slack alert
        /notify.sh "One or more backups on database host $TARGET_DATABASE_HOST failed. The error details are included below:" "$logcontents"
    fi

    echo -e "kubernetes-s3-mysql-backup encountered 1 or more errors. Exiting with status code 1."
    exit 1

else

    # If Slack alerts are enabled, send a notification that all database backups were successful
    if [ "$NOTIFY_ENABLED" = true ]
    then
        /notify.sh "Backup created: $backup_name"
    fi

    exit 0

fi
