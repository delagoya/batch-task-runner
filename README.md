# AWS Batch Task Runner

**NOTE**: This is highly experimental code and not meant to be used!


A POC for running jobs on AWS Batch that:

1. stage data to a local disk
2. run a sibling container to process the inputs
3. then stages a defined set of outputs back to S3 locations.

For expediancy's sake, we leveraged [OHSU's Funnel Project](https://ohsu-comp-bio.github.io/funnel/) to implement the above. We have a custom build of Funnel that is able to run a Task using only the worker process (e.g. the worker does not communicate with a leader Funnel service). You need only give it a JSON formatted [Task definition file](https://ohsu-comp-bio.github.io/funnel/docs/tasks/). Here is an example that downloads a file, calculates the MD5 checksum of the file, redirects the `STDOUT` of the process to a result file, then uploads that result to a S3 object:

```json
{
  "name": "S3 Get/Put example",
  "description": "Task inputs and outputs can be URLs.",
  "executors": [
    {
      "image": "ubuntu",
      "command": ["sh","-c","md5sum /tmp/inputfile > /tmp/md5sum.txt"]
    }
  ],
  "inputs": [
    {
      "name": "input",
      "description": "Download a public file from S3 Storage (IRS form 990 data)",
      "url": "http://example.com/index.html",
      "path": "/tmp/inputfile"
    }
    ],
    "outputs": [
      {
        "name": "checksum",
        "url": "s3://mybucket/results/md5sum.txt",
        "path": "/tmp/md5sum.txt"
      }
    ]
}
```

In order for Funnel to work in this way, it needs the Task file on local disk. We have provided a [Docker container](https://hub.docker.com/r/delagoya/funnel-wff/) with the custom built Funnel executable, and a [small wrapper script](bin/runtask.sh) that handles localization of task file and running the Funnel worker with the right command line arguments.


To make the above work with AWS Batch, we need a valid AWS Batch environment that has access to the target S3 bucket. Assume that this is the case, and that we have a Task IAM Role with the proper permissions, `exampleEcsTaskRole`.

The AWS Batch Job Definition that runs this container will need provide the proper mount points to enable launching of sibling containers.

**IMPORTANT!:** For the POC it is important that the mount points from the host instance, the container that AWS Batch launches, and the sibling container that Funnel launches all match. Otherwise you will get unexpected results. In the future we will make this a little more robust, but for the POC we assume that the root of where all processes write to will be a bind mount from the host named `/scratch`

Here is a example AWS Batch Job Definition to run :

```json
{
    "jobDefinitions": [
        {
            "jobDefinitionName": "TaskRunner",
            "type": "container",
            "parameters": {
                "TaskFile": "https://raw.githubusercontent.com/ohsu-comp-bio/funnel/master/examples/hello-world.json",
                "WorkDir": "/scratch"
            },
            "retryStrategy": {
                "attempts": 1
            },
            "containerProperties": {
                "image": "delagoya/funnel-wff:latest",
                "vcpus": 2,
                "memory": 2000,
                "command": [
                    "runtask.sh",
                    "Ref::TaskFile",
                    "Ref::WorkDir"
                ],
                "jobRoleArn": "arn:aws:iam::123412341234:role/exampleEcsTaskRole",
                "volumes": [
                    {
                        "host": {
                            "sourcePath": "/scratch"
                        },
                        "name": "scratch"
                    },
                    {
                        "host": {
                            "sourcePath": "/var/run/docker.sock"
                        },
                        "name": "docker_daemon"
                    }
                ],
                "environment": [],
                "mountPoints": [
                    {
                        "containerPath": "/scratch",
                        "readOnly": false,
                        "sourceVolume": "scratch"
                    },
                    {
                        "containerPath": "/var/run/docker.sock",
                        "readOnly": false,
                        "sourceVolume": "docker_daemon"
                    }
                ],
                "ulimits": []
            }
        }
    ]
}
```

Running the task would be:

```
$ aws batch submit-job --job-name task-runner-test --job-queue myQueue --job-definition TaskRunner:1
{
    "jobName": "task-runner-test",
    "jobId": "b9d25ef9-ddb8-40fb-aaf1-65c4b72113b4"
}
```

```
$ aws batch describe-jobs --jobs "b9d25ef9-ddb8-40fb-aaf1-65c4b72113b4"
```
```json
{
    "jobs": [
        {
            "jobName": "task-runner-test",
            "jobId": "b9d25ef9-ddb8-40fb-aaf1-65c4b72113b4",
            "jobQueue": "arn:aws:batch:us-east-1:798375407761:job-queue/testNewQueue",
            "status": "SUCCEEDED",
            "attempts": [ #...   ],
            "statusReason": "Essential container in task exited",
            # ... more output ...
                "exitCode": 0,
                "containerInstanceArn": "arn:aws:ecs:us-east-1:798375407761:container-instance/d20c0229-2d4c-46ca-b7f4-dd6701105803",
                "taskArn": "arn:aws:ecs:us-east-1:798375407761:task/00c4a49e-da3c-48b7-88ed-6ca389ad7e01",
                "logStreamName": "TaskRunner/default/00c4a49e-da3c-48b7-88ed-6ca389ad7e01"
            }
        }
    ]
}

```

You can view the output of the process from CloudWatch Logs (CWL) using the CLI and the above CWL log stream name. I've made the command that Funnel executed in **`bold text`**

```shell
$ aws logs get-log-events --log-group-name "/aws/batch/job"  --log-stream-name "TaskRunner/default/00c4a49e-da3c-48b7-88ed-6ca389ad7e01"
```
```
{
    "events": [
        {
            "timestamp": 1530802847405,
            "message": "Completed 187 Bytes/187 Bytes (3.4 KiB/s) with 1 file(s) remaining\rdownload: s3://cromwell-aws-batch/funnel/examples/hello-world.json to ./b7c96c645f5a4aeb0e4b21df8843596f.json",
            "ingestionTime": 1530802849093
        },
        {
            "timestamp": 1530802847610,
            "message": "{\"BuildDate\":\"\",\"GitBranch\":\"\",\"GitCommit\":\"\",\"GitUpstream\":\"\",\"Version\":\"unknown\",\"attempt\":0,\"index\":0,\"level\":\"info\",\"msg\":\"Version\",\"ns\":\"worker\",\"taskID\":\"bcv357t3fkig04kddet0\",\"time\":\"2018-07-05T15:00:47Z\",\"timestamp\":\"2018-07-05T15:00:47.608643019Z\"}",
            "ingestionTime": 1530802849093
        }
        # ... yada yada logs
```
The log message for actual command run by Funnel was:
```json
{
    "attempt": 0,
    "cmd": "docker run -i --read-only --rm --name bcv357t3fkig04kddet0-0 -v /scratch/funnel-work-dir/bcv357t3fkig04kddet0/tmp:/tmp:rw alpine echo hello world",
    "index": 0,
    "level": "info",
    "msg": "Running command",
    "ns": "worker",
    "taskID": "bcv357t3fkig04kddet0",
    "time": "2018-07-05T15:00:47Z",
    "timestamp": "2018-07-05T15:00:47.919952906Z"
}
```
