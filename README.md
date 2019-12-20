# Deployment Notifier
This script (notifier.sh) notifies slack channels when a new deploy using ECS is and actively serving requests.

## The problem
There is a disconnect between our current CI/CD pipelines and the infrastructure that runs our monolith API. Bitbucket Pipelines takes care of building the docker images, pushing them up to ECR, generating a new ECS task definition, and then updating the ECS service to use the new image/task. After that, the pipeline is finished - as it has fulfilled its duties and does not have visibility into AWS ECS.
What happens next behind the scenes in AWS:
- ECS scheduler sees our service using the newly updated task definition
- A new task (fargate container) is scheduled to run with our new docker image (task status will be `PROVISIONING`)
- After resources have been allocated for the new task, the container will boot up (task status will be `RUNNING`)
- The container initializes and starts listening for requests on its service port
- The target group picks up on the new task running with a network-accessible port and begins health checks (target status `initial`)
- After 2 successful health checks the target group will deem the new task healthy, and then start routing traffic to it (target status `healthy`)
- After the new task is healthy, the target group will start draining connections to the older task before removing it from the target group entirely (old target status `draining`)
- After about 30 seconds the old task will then be removed from the target group and then the ECS scheduler will shut the container down
That whole process takes between 5 and 10 minutes usually, and requests to the newly deployed version of our API won't be live until all steps are completed.

## The solution
Using the `awscli` one can get JSON data back about nearly every resource in AWS. By requesting the ECS task data specific to the environment/cluster in question, one can compare it to the desired task definition of our deployment to determine if it is live or not. Now we have a way to know for sure if our new code is running, or if we must continue to wait for ECS to catch up with our new deployment.
After the script determines the new deployment is live, it alerts us in slack channels specific to the deployment environment (prod vs. non-prod)

## Requirements
The solution must not hold up deployments to downstream environments: a deploy to dev (with notification) should not wait to be live before allowing the user to deploy to staging. So the notifier cannot live in the same pipeline, else it would slow down the development process.
The solution must be environment aware.
The solution must report back the environment and branch OR tag identifier.

### Data flow
At a high level the data flow is as such:
New branch is deployed to development -> Bitbucket Pipelines uses the `trigger-pipeline` pipe found here: https://bitbucket.org/atlassian/trigger-pipeline/src/master/ (which is basically fire and forget, allowing the pipeline to finish without waiting) -> the deployment-notifier custom pipeline is triggered (being passed in the data it requires) -> the notifier.sh script watches the ECS data until all tasks are using the new task definition -> sends a slack notification to the proper channel once live (using a custom slack app via https://api.slack.com/slack-apps)